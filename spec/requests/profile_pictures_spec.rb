require "rails_helper"

RSpec.describe "The user's picture (USR-07)" do
  let(:user) { create(:user, name: "Demo Dispatcher", email_address: "dispatcher@example.com") }
  let(:refusal) { "Picture must be a JPEG, PNG or WebP image of at most 2 MB" }

  def page = response.parsed_body

  def send_picture(file) = patch(profile_picture_path, params: { user: { avatar: file } })

  def named(fixture, name, type) = Rack::Test::UploadedFile.new(file_fixture(fixture), type, original_filename: name)

  context "when signed in" do
    before { sign_in_as(user) }

    it "is changed from the profile, in a dialog with three ways", :aggregate_failures do
      get profile_path
      link = page.at_css("main a[href='#{edit_profile_picture_path}']")
      expect([ link.text.strip, link["data-turbo-frame"] ]).to eq([ "Change picture", "modal" ])

      get edit_profile_picture_path
      dialog = page.at_css("turbo-frame#modal dialog")
      expect(dialog.at_css("#dialog-title").text).to eq("Picture")
      upload = dialog.at_css("form[action='#{profile_picture_path}'][enctype='multipart/form-data']")
      expect(upload.at_css("input[type=file]")["accept"]).to eq("image/jpeg,image/png,image/webp")
      expect(dialog.at_css("form[action='#{gravatar_profile_picture_path}'] button").text.strip).to eq("Take from Gravatar")
      expect(dialog.text.squish).to include("JPEG, PNG or WebP, up to 2 MB", "asks gravatar.com once", "never turn to gravatar.com")
    end

    it "gives the file field a label and a hint, and offers Remove only when there is a picture", :aggregate_failures do
      get edit_profile_picture_path
      expect(fields_without_label_or_hint(page)).to be_empty
      expect(page.css("dialog input[name=_method][value=delete]")).to be_empty

      send_picture(fixture_file_upload("photo.jpg"))
      get edit_profile_picture_path
      expect(page.at_css("dialog form[action='#{profile_picture_path}'] input[name=_method][value=delete] ~ button").text.strip).to eq("Remove")
    end

    it "keeps a photo of each kind and tells so", :aggregate_failures do
      { "photo.jpg" => "image/jpeg", "photo.png" => "image/png", "photo.webp" => "image/webp" }.each do |name, kind|
        send_picture(fixture_file_upload(name))

        expect(response).to have_http_status(:see_other)
        expect([ response.location, flash[:notice] ]).to eq([ profile_url, "Picture saved" ])
        expect(user.reload.avatar.content_type).to eq(kind)
      end
      expect(ActiveStorage::Attachment.where(record: user).count).to eq(1)
    end

    it "shows the picture where the initials stood: in the header, in the account menu and on the profile", :aggregate_failures do
      send_picture(fixture_file_upload("photo.png"))
      get profile_path
      address = user_picture_path(user, v: user.reload.avatar.blob.id)

      button = page.at_css("header button[popovertarget='account-menu']")
      expect(button.at_css("img.avatar").to_h.slice("src", "alt")).to eq("src" => address, "alt" => "")
      expect(button.text.squish).to eq("Account, Demo Dispatcher")
      expect(page.at_css("#account-menu .account img.avatar")["src"]).to eq(address)
      expect(page.at_css("main section[aria-label='Account'] img.avatar")["src"]).to eq(address)
    end

    it "refuses what is not a JPEG, PNG or WebP image, whatever it is called, and keeps the former picture", :aggregate_failures do
      send_picture(fixture_file_upload("photo.jpg"))
      [ fixture_file_upload("photo.gif"), named("note.txt", "photo.png", "image/png"), named("photo.gif", "photo.jpg", "image/jpeg") ].each do |file|
        send_picture(file)

        expect(response).to have_http_status(:see_other)
        expect([ response.location, flash[:alert] ]).to eq([ profile_url, refusal ])
      end
      expect(user.reload.avatar.content_type).to eq("image/jpeg")
    end

    it "refuses a photo of more than 2 MB and one of no bytes", :aggregate_failures do
      heavy = Tempfile.new([ "heavy", ".jpg" ], binmode: true).tap { |file| file.write(file_fixture("photo.jpg").binread, "0" * 2.megabytes) }
      empty = Tempfile.new([ "empty", ".jpg" ])
      [ heavy, empty ].each do |file|
        send_picture(Rack::Test::UploadedFile.new(file.tap(&:rewind), "image/jpeg"))

        expect([ response.location, flash[:alert] ]).to eq([ profile_url, refusal ])
      end
      expect(user.reload.avatar).not_to be_attached
    end

    it "refuses a request without a photo, or with words in its place", :aggregate_failures do
      [ {}, { user: { avatar: "photo.jpg" } }, { user: "photo.jpg" } ].each do |sent|
        patch profile_picture_path, params: sent

        expect([ response.location, flash[:alert] ]).to eq([ profile_url, "Choose a photo" ])
      end
    end

    it "removes the picture and its file, and the initials come back", :aggregate_failures do
      send_picture(fixture_file_upload("photo.jpg"))
      delete profile_picture_path

      expect(response).to have_http_status(:see_other)
      expect([ response.location, flash[:notice] ]).to eq([ profile_url, "Picture removed" ])
      expect([ user.reload.avatar.attached?, ActiveStorage::Blob.count ]).to eq([ false, 0 ])
      get profile_path
      expect(page.at_css("header button[popovertarget='account-menu'] span.avatar").text.strip).to eq("DD")
    end

    describe "from Gravatar" do
      let(:http) { instance_double(Net::HTTP) }
      let(:found) do
        Net::HTTPOK.new("1.1", "200", "OK").tap do |answer|
          allow(answer).to receive_messages(body: file_fixture("photo.png").binread, content_type: "image/png")
        end
      end

      def gravatar_answers(answer)
        allow(http).to receive(:get).and_return(answer)
        allow(Net::HTTP).to receive(:start).and_yield(http)
      end

      it "asks for the picture of the address once, by its SHA-256, and keeps the answer", :aggregate_failures do
        gravatar_answers(found)
        post gravatar_profile_picture_path

        expect([ response.location, flash[:notice] ]).to eq([ profile_url, "Picture taken from Gravatar" ])
        expect(user.reload.avatar.content_type).to eq("image/png")
        expect(Net::HTTP).to have_received(:start).once.with("gravatar.com", 443, use_ssl: true, open_timeout: 5, read_timeout: 5)
        expect(http).to have_received(:get).with("/avatar/#{Digest::SHA256.hexdigest('dispatcher@example.com')}?d=404&s=256")
      end

      it "says so when Gravatar has no picture for the address, and keeps the former one", :aggregate_failures do
        send_picture(fixture_file_upload("photo.jpg"))
        gravatar_answers(Net::HTTPNotFound.new("1.1", "404", "Not Found"))
        post gravatar_profile_picture_path

        expect([ response.location, flash[:alert] ]).to eq([ profile_url, "Gravatar has no picture for your address" ])
        expect(user.reload.avatar.content_type).to eq("image/jpeg")
      end

      it "says so when Gravatar does not answer" do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
        post gravatar_profile_picture_path

        expect(flash[:alert]).to eq("Gravatar did not answer. Try again later")
      end

      it "keeps no answer that is not a picture", :aggregate_failures do
        allow(found).to receive_messages(body: "<html>not a picture</html>", content_type: "text/html")
        gravatar_answers(found)
        post gravatar_profile_picture_path

        expect(flash[:alert]).to eq("Gravatar has no picture for your address")
        expect(user.reload.avatar).not_to be_attached
      end

      it "is not asked when a page is shown or a photo is sent" do
        allow(Net::HTTP).to receive(:start)
        send_picture(fixture_file_upload("photo.jpg"))
        [ profile_path, edit_profile_picture_path, user_picture_path(user), root_path ].each { |shown| get shown }

        expect(Net::HTTP).not_to have_received(:start)
      end
    end

    describe "sending the picture" do
      before { send_picture(fixture_file_upload("photo.jpg")) }

      it "sends it with its kind, for the browser to keep to itself for a day", :aggregate_failures do
        get user_picture_path(user)

        expect(response).to have_http_status(:ok)
        expect(response.body.b).to eq(file_fixture("photo.jpg").binread)
        expect(response.headers.values_at("content-type", "cache-control")).to eq([ "image/jpeg", "max-age=86400, private" ])
        expect(response.headers["content-disposition"]).to start_with("inline")
      end

      it "sends it to any signed-in user, and nothing for a user without a picture", :aggregate_failures do
        other = create(:user)
        sign_in_as(other)

        get user_picture_path(user)
        expect(response).to have_http_status(:ok)
        get user_picture_path(other)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  it "is the crew's too: it changes its picture and sees it", :aggregate_failures do
    crew = create(:user, :crew)
    sign_in_as(crew)

    get edit_profile_picture_path
    expect(response).to have_http_status(:ok)
    send_picture(fixture_file_upload("photo.jpg"))
    expect(flash[:notice]).to eq("Picture saved")
    get user_picture_path(crew)
    expect(response).to have_http_status(:ok)
    delete profile_picture_path
    expect(crew.reload.avatar).not_to be_attached
  end

  it "is not for a visitor without a sign-in", :aggregate_failures do
    allow(Net::HTTP).to receive(:start)
    [ -> { get edit_profile_picture_path }, -> { send_picture(fixture_file_upload("photo.jpg")) },
      -> { post gravatar_profile_picture_path }, -> { delete profile_picture_path }, -> { get user_picture_path(user) } ].each do |request|
      request.call

      expect(response).to redirect_to(new_session_path)
    end
    expect([ user.reload.avatar.attached?, ActiveStorage::Blob.count ]).to eq([ false, 0 ])
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "stands beside each name in the list of users, the initials where there is none", :aggregate_failures do
    sign_in_as(user)
    send_picture(fixture_file_upload("photo.jpg"))
    administrator = create(:user, :administrator, name: "Demo Administrator")
    sign_in_as(administrator)
    get users_path

    rows = page.css("table.data-table tbody tr").to_h { |row| [ row.at_css("td[data-label=Name] a").text.strip, row ] }
    expect(rows["Demo Dispatcher"].at_css("td[data-label=Name] img.avatar")["src"]).to eq(user_picture_path(user, v: user.reload.avatar.blob.id))
    expect(rows["Demo Administrator"].at_css("td[data-label=Name] span.avatar").text.strip).to eq("DA")
  end
end
