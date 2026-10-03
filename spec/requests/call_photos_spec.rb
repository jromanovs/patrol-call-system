require "rails_helper"

RSpec.describe "The crew's photos (CRW-10, BR-19)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let(:crew) { create(:user, :crew, name: "Demo Crew", patrol_car: car) }
  let(:dispatcher) { create(:user) }
  let(:call) { create(:alarm_call) }

  def page = response.parsed_body

  def refusal = "Photo must be a JPEG, PNG or WebP image of at most 5 MB"

  # The photo controller waits for the server's answer, holds a refresh of the
  # page while the photos are on their way, and gets ready for the next choice.
  def wiring = "turbo:before-fetch-response@document->photo#answer turbo:before-visit@document->photo#hold " \
               "turbo:submit-end@document->photo#reset"

  def upload(*names) = names.map { |name| fixture_file_upload(name) }

  def on_scene(call = self.call, car = self.car)
    CallStep.new(call, dispatcher).dispatch(car)
    CallStep.new(call.reload, dispatcher).arrive
    call.reload
  end

  describe "added by the crew" do
    before { sign_in_as(crew) }

    it "keeps photos taken on site, several at once, with the crew user, and shows them on its screen",
       :aggregate_failures do
      on_scene
      post call_photos_path(call), params: { photos: upload("photo.jpg", "photo.webp") }

      expect(response).to redirect_to(crew_path)
      expect(call.photos.map { |photo| [ photo.user, photo.image.content_type ] })
        .to contain_exactly([ crew, "image/jpeg" ], [ crew, "image/webp" ])
      follow_redirect!
      expect(page.at_css(".crew-photos").text.squish)
        .to include("Photos", "2 taken", "Take photo", "Photos go to the call; the dispatcher sees them at once.")
      expect(page.css(".crew-photos img").map { |image| image["src"] })
        .to eq(call.photos.order(:id).map { |photo| call_photo_path(call, photo) })
    end

    it "offers the camera and the library on its screen, the photos shrunk before they are sent", :aggregate_failures do
      on_scene
      get crew_path

      input = page.at_css(".crew-photos input[type=file]")
      expect([ input["name"], input["accept"], input["multiple"] ]).to eq([ "photos[]", "image/*", "multiple" ])
      expect(input["data-action"]).to eq("change->photo#send")
      expect(page.at_css(".crew-photos")["data-action"]).to eq(wiring)
      expect(page.at_css(".crew-photos [data-photo-target=status]")["role"]).to eq("status")
      expect(page.at_css("form##{input['form']}")["action"]).to eq(call_photos_path(call))
    end

    it "has no photos before its car is on site" do
      CallStep.new(call, dispatcher).dispatch(car)
      CallStep.new(call.reload, dispatcher).accept
      get crew_path

      expect(page.at_css(".crew-photos")).to be_nil
    end

    it "refuses a choice with a file that is not a photo, and keeps none of it", :aggregate_failures do
      on_scene
      post call_photos_path(call), params: { photos: upload("photo.jpg", "note.txt") }

      expect(response).to redirect_to(crew_path)
      expect(flash[:alert]).to eq(refusal)
      expect(call.photos).to be_empty
    end

    it "refuses anything sent in place of a file", :aggregate_failures do
      on_scene
      post call_photos_path(call), params: { photos: [ "some-signed-id", { io: "x" } ] }

      expect(flash[:alert]).to eq(refusal)
      expect(call.photos).to be_empty
    end

    it "asks for a photo when none is chosen" do
      on_scene
      post call_photos_path(call), params: { photos: [ "" ] }

      expect(flash[:alert]).to eq("Choose a photo")
    end

    it "adds photos only while its car is on site, and only to its own car's call", :aggregate_failures do
      CallStep.new(call, dispatcher).dispatch(car)
      post call_photos_path(call), params: { photos: upload("photo.jpg") }
      expect(flash[:alert]).to eq("Not allowed for your role")

      other = on_scene(create(:alarm_call), create(:patrol_car))
      post call_photos_path(other), params: { photos: upload("photo.jpg") }
      expect(flash[:alert]).to eq("Not allowed for your role")

      expect(CallPhoto.count).to eq(0)
    end

    it "adds photos from the closing dialog, which changes only their row", :aggregate_failures do
      on_scene
      get new_call_closing_path(call), headers: { "Turbo-Frame" => "modal" }
      input = page.at_css("turbo-frame#modal turbo-frame#closing-photos .closing-photos input[type=file]")
      form = page.at_css("form##{input['form']}")
      expect([ form["action"], form["data-turbo-frame"] ]).to eq([ call_photos_path(call), "closing-photos" ])
      expect(page.at_css(".closing-photos")["data-action"]).to eq(wiring)

      post call_photos_path(call), params: { photos: upload("photo.png"), from: "closing" },
                                   headers: { "Turbo-Frame" => "closing-photos" }
      expect(response).to redirect_to(new_call_closing_path(call))

      get new_call_closing_path(call), headers: { "Turbo-Frame" => "closing-photos" }
      row = page.at_css("turbo-frame#closing-photos .closing-photos")
      expect(row.text.squish).to include("1 photo attached", "Add photo")
      expect(row.css("img").map { |image| image["src"] }).to eq([ call_photo_path(call, call.photos.sole) ])
    end

    it "is told in the closing dialog's row why a photo was refused", :aggregate_failures do
      on_scene
      post call_photos_path(call), params: { photos: upload("photo.gif"), from: "closing" },
                                   headers: { "Turbo-Frame" => "closing-photos" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css("turbo-frame#closing-photos .closing-photos").text).to include(refusal)
      expect(call.photos).to be_empty
    end
  end

  describe "by the staff" do
    before { sign_in_as(dispatcher) }

    it "is not added", :aggregate_failures do
      on_scene
      post call_photos_path(call), params: { photos: upload("photo.jpg") }

      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(CallPhoto.count).to eq(0)
    end

    it "is not offered in the closing dialog" do
      on_scene
      get new_call_closing_path(call), headers: { "Turbo-Frame" => "modal" }

      expect(page.at_css("#closing-photos, .closing-photos, input[type=file]")).to be_nil
    end
  end

  describe "sent" do
    let!(:photo) do
      create(:call_photo, call: on_scene, user: crew,
                          image: Rack::Test::UploadedFile.new(file_fixture("photo.jpg"), "image/jpeg", original_filename: "x.html"))
    end

    def fetched_by(user, path = call_photo_path(call, photo))
      sign_in_as(user)
      get path
      [ response.media_type, response.body.b == file_fixture("photo.jpg").binread.b, response.headers["Cache-Control"] ]
    end

    it "to the staff, kept privately, shown and not sniffed, named by its kind", :aggregate_failures do
      expect(fetched_by(dispatcher)).to eq([ "image/jpeg", true, "max-age=86400, private" ])
      expect(response.headers["Content-Disposition"]).to start_with("inline; filename=\"call-#{call.id}-photo-#{photo.id}.jpg\"")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end

    it "to the crew of the call's car while the call is active" do
      expect(fetched_by(crew)).to eq([ "image/jpeg", true, "max-age=86400, private" ])
    end

    it "to no crew once the call is closed", :aggregate_failures do
      CallStep.new(call, dispatcher).close("other", "")
      fetched_by(crew)

      expect(response).to redirect_to(crew_path)
      expect(flash[:alert]).to eq("Not allowed for your role")
    end

    it "to no other crew and no one signed out", :aggregate_failures do
      get call_photo_path(call, photo)
      expect(response).to redirect_to(new_session_path)

      fetched_by(create(:user, :crew, patrol_car: create(:patrol_car)))
      expect(response).to redirect_to(crew_path)
      expect(flash[:alert]).to eq("Not allowed for your role")
    end

    it "only under its own call" do
      other = create(:alarm_call)
      fetched_by(dispatcher, call_photo_path(other, photo))

      expect(response).to have_http_status(:not_found)
    end

    it "as not found when its file is gone" do
      ActiveStorage::Blob.service.delete(photo.image.key)
      fetched_by(dispatcher)

      expect(response).to have_http_status(:not_found)
    end
  end

  it "shows the staff the crew's photos on the call page, with time and user, each opening in full (DSP-02)",
     :aggregate_failures do
    photo = travel_to(Time.zone.local(2026, 10, 3, 10, 14)) { create(:call_photo, call: on_scene, user: crew) }
    sign_in_as(dispatcher)
    get call_path(call)

    figure = page.at_css(".call-photos figure")
    expect([ figure.at_css("a")["href"], figure.at_css("img")["src"], figure.at_css("figcaption").text.squish ])
      .to eq([ call_photo_path(call, photo), call_photo_path(call, photo), "10:14 · Demo Crew" ])
    expect(page.at_css(".call-photos h2").text).to eq("Photos")
  end
end
