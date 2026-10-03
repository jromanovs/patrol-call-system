require "rails_helper"

RSpec.describe "The crew's SOS from its screen (CRW-11, ADD-12, BR-21)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-07") }
  let(:helper) { create(:patrol_car, call_sign: "P-03") }
  let(:crew) { create(:user, :crew, patrol_car: car) }
  let(:dispatcher) { create(:user, name: "Demo Dispatcher") }

  before do
    travel_to(now)
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: true))
    CrewSosController::COUNTS.clear
    sign_in_as(crew)
  end

  after { travel_back }

  def page = response.parsed_body

  def now = Time.zone.local(2026, 10, 3, 19, 47)

  def place = { latitude: "56.95", longitude: "24.1", accuracy: "8" }

  def state = page.at_css(".crew-sos-state")&.text&.squish

  describe "the button, guarded against a press by mistake" do
    it "stands apart from the steps of a call and opens a question, sending nothing itself", :aggregate_failures do
      CallStep.new(create(:alarm_call, guarded_site: create(:guarded_site)), dispatcher).dispatch(car)
      get crew_path

      button = page.at_css(".crew-sos a")
      expect([ button.text.squish, button["href"], button["data-turbo-frame"] ]).to eq([ "SOS", new_crew_sos_path, "modal" ])
      expect(page.at_css(".crew-actions .crew-sos, .crew-sos form")).to be_nil
      expect(SosCall.count).to eq(0)
    end

    it "asks first: the question closes by itself after 15 seconds, and only its own button sends", :aggregate_failures do
      get new_crew_sos_path

      dialog = page.at_css("turbo-frame#modal dialog")
      expect([ dialog.at_css("#dialog-title").text, dialog["data-dialog-timeout-value"] ]).to eq([ "Send SOS?", "15" ])
      expect(dialog.text.squish).to include("the crew of P-07 needs help", "Nothing is sent until Send SOS is pressed")
      expect(dialog.at_css("form[action='#{crew_sos_path}'][method=post] button").text.squish).to eq("Send SOS")
      expect(dialog.css("button[data-action='dialog#close']").map { |button| button.text.squish }).to include("Not now")
      expect(SosCall.count).to eq(0)
    end

    it "can say that the signal did not go, for when the server gives no answer", :aggregate_failures do
      get new_crew_sos_path

      failed = page.at_css("dialog [data-dialog-target=failed]")
      expect([ failed.text.squish, failed.key?("hidden"), failed["role"] ])
        .to eq([ "Not sent: no answer from the server. Press Send SOS again, or call the dispatcher by radio.", true, "alert" ])
    end

    it "sends where the phone is, waiting for it 3 seconds at most and taking a position a minute old", :aggregate_failures do
      get new_crew_sos_path

      form = page.at_css("form[action='#{crew_sos_path}']")
      expect(form.to_h).to include("data-controller" => "position", "data-position-wait-value" => "3000",
                                   "data-position-age-value" => "60000", "data-turbo-frame" => "_top")
      expect(form.css("input[type=hidden][data-position-target]").map { |input| input["name"] })
        .to eq(%w[ latitude longitude accuracy ])
    end
  end

  describe "sending (ADD-12)" do
    it "registers the car's SOS where the phone is, by the crew user", :aggregate_failures do
      post crew_sos_path, params: place

      expect(response).to redirect_to(crew_path)
      expect(SosCall.sole).to have_attributes(raised_by: car, registered_by: crew, latitude: 56.95, longitude: 24.1,
                                              accuracy: 8, signals: 1, placed_at: now, status: "pending",
                                              priority: "critical")
    end

    it "takes the newest kept position of the car, with its time, when the phone gives none" do
      create(:car_position, patrol_car: car, latitude: 56.9, longitude: 24.2, accuracy: 30, recorded_at: 40.minutes.ago)
      create(:car_position, patrol_car: car, latitude: 56.96, longitude: 24.11, accuracy: 20, recorded_at: 12.minutes.ago)
      post crew_sos_path

      expect(SosCall.sole).to have_attributes(latitude: 56.96, longitude: 24.11, accuracy: 20, placed_at: 12.minutes.ago)
    end

    it "goes without a place when there is none to give: a position off the earth, a kept one older than 30 days" do
      create(:car_position, patrol_car: car, recorded_at: 31.days.ago)
      post crew_sos_path, params: place.merge(latitude: "91")

      expect(SosCall.sole).to have_attributes(latitude: nil, longitude: nil, accuracy: nil, placed_at: nil, signals: 1)
    end

    it "counts a further press in the active call, with the new place" do
      post crew_sos_path
      post crew_sos_path, params: place

      expect(SosCall.sole).to have_attributes(signals: 2, latitude: 56.95, registered_by: crew)
    end

    it "leaves the place as it was when a further press brings none, or only an older kept position",
       :aggregate_failures do
      post crew_sos_path, params: place
      post crew_sos_path
      expect(SosCall.sole).to have_attributes(signals: 2, latitude: 56.95, longitude: 24.1, accuracy: 8)

      create(:car_position, patrol_car: car, latitude: 56.9, longitude: 24.2, recorded_at: 12.minutes.ago)
      post crew_sos_path
      expect(SosCall.sole).to have_attributes(signals: 3, latitude: 56.95, placed_at: now)
    end

    it "tells the crew when the signal could not be registered", :aggregate_failures do
      allow(SosCall).to receive(:signal).and_return(nil)
      post crew_sos_path, params: place

      expect(response).to redirect_to(crew_path)
      expect(flash[:alert]).to eq("The SOS was not sent. Press SOS again, or call the dispatcher by radio")
    end

    it "takes at most 10 signals a minute from one user, and says so", :aggregate_failures do
      11.times { post crew_sos_path, params: place }

      expect(SosCall.sole.signals).to eq(10)
      expect(response).to redirect_to(crew_path)
      expect(flash[:alert]).to eq("Too many signals in a minute; the dispatcher has your SOS")
    end

    it "is only for a crew", :aggregate_failures do
      sign_in_as(dispatcher)
      post crew_sos_path, params: place
      expect(flash[:alert]).to eq("Not allowed for your role")

      get new_crew_sos_path
      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(SosCall.count).to eq(0)
    end

    it "tells the open pages of the staff at once (DYN-19)" do
      expect { post crew_sos_path, params: place }.to have_broadcasted_to("sos").with { |stream|
        expect(stream).to include("SOS from P-07", "Position accuracy 8 m")
      }
    end
  end

  describe "the state of the SOS on the screen of the crew that asked (CRW-11)" do
    it "says that the signal is sent, then seen, then which car comes, for a signal of Traccar Client too",
       :aggregate_failures do
      call = SosCall.signal(car, { latitude: 56.95, longitude: 24.1, accuracy: 9 })
      get crew_path
      expect(state).to eq("SOS sent at 19:47 The dispatcher has not acknowledged it yet.")

      travel_to(now + 2.minutes)
      call.acknowledge(dispatcher)
      get crew_path
      expect(state).to eq("The dispatcher has seen your SOS Sent at 19:47 · acknowledged at 19:49")

      travel_to(now + 3.minutes)
      CallStep.new(call.reload, dispatcher).dispatch(helper)
      get crew_path
      expect(state).to eq("P-03 is sent to you P-03 dispatched at 19:50")
    end

    it "follows the car that is sent: accepted, then arrived", :aggregate_failures do
      call = SosCall.signal(car, {})
      helpers = create(:user, :crew, patrol_car: helper)
      CallStep.new(call, dispatcher).dispatch(helper)

      travel_to(now + 1.minute)
      CallStep.new(call.reload, helpers).accept
      get crew_path
      expect(state).to eq("P-03 is sent to you P-03 dispatched at 19:47 · accepted at 19:48")

      travel_to(now + 9.minutes)
      CallStep.new(call.reload, helpers).arrive
      get crew_path
      expect(state).to eq("P-03 is sent to you P-03 dispatched at 19:47 · accepted at 19:48 · arrived at 19:56")
    end

    it "says again that the signal waits, when a further one follows the acknowledgement" do
      call = SosCall.signal(car, {})
      call.acknowledge(dispatcher)
      SosCall.signal(car, {})
      get crew_path

      expect(state).to eq("SOS sent at 19:47 The dispatcher has not acknowledged it yet.")
    end

    it "comes without sound: nothing of it is read out" do
      post crew_sos_path, params: place
      get crew_path

      block = page.at_css(".crew-sos-state")
      expect([ block["role"], block["aria-live"], block.ancestors("[role=status], [role=alert], [aria-live]").size ])
        .to eq([ nil, nil, 0 ])
    end

    it "sends no notice to the phones of the crew that asked, only to the crew sent to help", :aggregate_failures do
      create(:push_subscription, user: crew)
      phone = create(:push_subscription, user: create(:user, :crew, patrol_car: helper))
      sent = []
      allow(WebPush).to receive(:payload_send) { |**notice| sent << notice[:endpoint] }

      perform_enqueued_jobs(only: CrewNoticeJob) do
        post crew_sos_path, params: place
        SosCall.sole.acknowledge(dispatcher)
        CallStep.new(SosCall.sole, dispatcher).dispatch(helper)
      end

      expect(sent).to eq([ phone.endpoint ])
    end

    it "stays beside the crew's own call, and offers to send again while the SOS is active", :aggregate_failures do
      CallStep.new(create(:alarm_call, guarded_site: create(:guarded_site, name: "Demo Shop 10")), dispatcher).dispatch(car)
      post crew_sos_path, params: place
      get crew_path

      expect(state).to start_with("SOS sent at 19:47")
      expect(page.at_css(".crew-call").text).to include("Demo Shop 10")
      expect(page.at_css(".crew-sos a").text.squish).to eq("Send SOS again")
    end

    it "goes when the call ends, and the plain button returns", :aggregate_failures do
      post crew_sos_path, params: place
      CallStep.new(SosCall.sole, dispatcher).cancel("Pressed by mistake")
      get crew_path

      expect(state).to be_nil
      expect(page.at_css(".crew-sos a").text.squish).to eq("SOS")
    end

    it "leaves the crew no way to cancel its SOS", :aggregate_failures do
      post crew_sos_path, params: place
      get crew_path
      expect(page.css(".crew-sos-state a, .crew-sos-state form, .crew-sos form")).to be_empty

      post call_cancellation_path(SosCall.sole), params: { reason: "Never mind" }
      expect(SosCall.sole.status).to eq("pending")
    end
  end

  describe "a signal without a place (BR-21)" do
    let(:call) { SosCall.signal(car, {}, by: crew) }

    before { call }

    it "is told to the staff by a strip and a card, without a mark on the map or a way to show it", :aggregate_failures do
      sign_in_as(dispatcher)
      get root_path

      strip = page.at_css("#sos-strips .sos-strip")
      expect(strip.text.squish).to include("SOS from P-07", "Place unknown")
      expect(strip.css("a").map { |link| link.text.squish }).to eq([ "Dispatch a car" ])
      expect(page.at_css(".call-card.sos").text.squish).to include("Crew of P-07", "Place unknown")
      expect(page.at_css(".call-card.sos .call-card-site")).to be_nil
      expect(page.at_css("li#map_sos_call_#{call.id}")).to be_nil
    end

    it "names a place taken from the car's last position by its time", :aggregate_failures do
      CallStep.new(call, dispatcher).cancel("Check")
      create(:car_position, patrol_car: car, latitude: 56.96, longitude: 24.11, accuracy: 20, recorded_at: 12.minutes.ago)
      post crew_sos_path
      sign_in_as(dispatcher)
      get root_path

      expect(page.at_css("#sos-strips .sos-strip").text.squish).to include("Last position of the car, at 19:35 · accuracy 20 m")
      expect(page.at_css("li#map_sos_call_#{SosCall.last.id}")["data-latitude"]).to eq("56.96")

      get call_path(SosCall.last)
      expect(page.at_css("dl.details").text.squish)
        .to include("56.960000, 24.110000 · accuracy 20 m · the car's last position, at 19:35")
      expect(api_get(api_v1_call_path(SosCall.last), user: dispatcher)["place"])
        .to include("placed_at" => (now - 12.minutes).iso8601)
    end

    it "opens on its page, in the list and in the API without a place", :aggregate_failures do
      sign_in_as(dispatcher)
      get call_path(call)
      details = page.css("dl.details > div").to_h { |row| [ row.at_css("dt").text.squish, row.at_css("dd").text.squish ] }
      expect(details).to include("Place" => "Unknown", "Registered by" => crew.name)

      get calls_path
      expect(response).to have_http_status(:ok)
      expect(api_get(api_v1_call_path(call), user: dispatcher)).to include("place" => nil, "registered_by" => crew.name)
    end

    it "takes a car sent to help: no map and no route, and Arrived keeps where the phone is without a distance",
       :aggregate_failures do
      CallStep.new(call, dispatcher).dispatch(helper)
      sign_in_as(create(:user, :crew, patrol_car: helper))
      get crew_path
      expect(page.at_css(".crew-call").text.squish).to include("Crew of P-07", "Place unknown")
      expect([ page.at_css(".crew-actions a.route"), page.at_css(".map-view") ]).to eq([ nil, nil ])

      post call_arrival_path(call), params: place
      expect(call.reload.arrival_position).to have_attributes(latitude: 56.95, distance: nil)
      get crew_path
      expect(page.at_css(".crew-call .arrival").text.squish).to include("the place of the signal is unknown")

      sign_in_as(dispatcher)
      get call_path(call)
      expect(page.at_css("dl.details").text.squish).to include("The place of the signal is unknown (56.950000, 24.100000)")
    end
  end
end
