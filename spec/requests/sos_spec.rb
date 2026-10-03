require "rails_helper"

RSpec.describe "A crew's SOS (BR-21, UPD-13, DSP-06, DYN-19)" do
  include_context "without the seeded records"

  let(:signalled) { Time.zone.local(2026, 10, 3, 19, 47) }
  let(:car) { create(:patrol_car, call_sign: "P-12", district: :north) }
  let(:helper) { create(:patrol_car, call_sign: "P-03") }
  let(:dispatcher) { create(:user, name: "Demo Dispatcher") }
  let(:call) do
    create(:sos_call, raised_by: car, latitude: 56.95, longitude: 24.1, accuracy: 12, received_at: signalled,
                      signals: 2, signalled_at: signalled + 1.minute)
  end

  before do
    travel_to(signalled + 2.minutes)
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: true))
    call
  end

  after { travel_back }

  def page = response.parsed_body

  def strip = page.at_css("#sos-strips .sos-strip")

  def streams = page.css("turbo-cable-stream-source").map { |source| Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"]) }

  describe "the strip on the pages of the staff (DSP-06, DYN-19)" do
    before { sign_in_as(dispatcher) }

    it "tells of the signal on the board and on every other page, and follows it without a reload", :aggregate_failures do
      [ root_path, calls_path, patrol_cars_path ].each do |path|
        get path

        expect(strip.text.squish).to include("SOS from P-12 · 19:47", "2 min ago", "Position accuracy 12 m",
                                             "2 signals, the last at 19:48")
        expect(streams).to include("sos")
      end
    end

    it "is read out when it comes, but not again with every minute it counts", :aggregate_failures do
      get root_path

      expect(strip.at_css("[role=alert]").text.squish).to eq("SOS from P-12 · 19:47")
      expect(strip.at_css("[data-waiting-target=minutes]").ancestors("[role=alert]")).to be_empty
    end

    it "offers to show the place, to acknowledge and to send a car", :aggregate_failures do
      get calls_path

      expect(strip.at_css("a[href='#{root_path(sos: call.id)}']").text.squish).to eq("Show on map")
      expect(strip.at_css("form[action='#{call_acknowledgement_path(call)}'] button").text.squish).to eq("Acknowledge")
      dispatch = strip.at_css("a[href='#{new_call_dispatch_path(call)}']")
      expect([ dispatch.text.squish, dispatch["data-turbo-frame"] ]).to eq([ "Dispatch a car", "modal" ])
    end

    it "names the call the asking car has" do
      site = create(:guarded_site, name: "Demo Shop 10")
      CallStep.new(create(:alarm_call, guarded_site: site), dispatcher).dispatch(car)
      get root_path

      expect(strip.text.squish).to include("P-12 has the call at Demo Shop 10")
    end

    it "sounds every 5 seconds, and can say that the browser holds the sound back", :aggregate_failures do
      get root_path

      strips = page.at_css("#sos-strips")
      expect(strips.to_h).to include("data-controller" => "sos", "data-sos-interval-value" => "5")
      hint = strips.at_css("[data-sos-target=hint]")
      expect([ hint.text.squish, hint.key?("hidden") ]).to eq([ "No sound yet: click or press a key on this page", true ])
    end

    it "is gone once the signal is acknowledged, comes back with a further signal, and goes with the call",
       :aggregate_failures do
      call.acknowledge(dispatcher)
      get root_path
      expect([ strip, page.at_css("#sos-strips").nil? ]).to eq([ nil, false ])

      SosCall.signal(car, { latitude: 56.96, longitude: 24.1, accuracy: 5 })
      get root_path
      expect(strip.text.squish).to include("3 signals")

      CallStep.new(call.reload, dispatcher).cancel("Pressed by mistake")
      get root_path
      expect(strip).to be_nil
    end

    it "shows every signal not acknowledged, the oldest first, without the sending of a car once one is sent",
       :aggregate_failures do
      other = create(:sos_call, raised_by: helper, received_at: signalled - 5.minutes)
      CallStep.new(other, dispatcher).dispatch(create(:patrol_car))
      other.update!(acknowledged_at: nil, acknowledged_by: nil)
      get root_path

      strips = page.css("#sos-strips .sos-strip")
      expect(strips.map { |one| one.at_css(".sos-words > div").text.squish })
        .to eq([ "SOS from P-03 · 19:42 · 7 min ago", "SOS from P-12 · 19:47 · 2 min ago" ])
      expect(strips.map { |one| one.css("a").map { |link| link.text.squish } })
        .to eq([ [ "Show on map" ], [ "Show on map", "Dispatch a car" ] ])
    end

    it "is not for the crew: neither the strip nor its stream", :aggregate_failures do
      sign_in_as(create(:user, :crew, patrol_car: helper))
      get crew_path

      expect(page.at_css("#sos-strips")).to be_nil
      expect(streams).not_to include("sos")
    end
  end

  describe "Acknowledge (UPD-13)" do
    it "records who saw the signal and when, and stays on the page it was pressed on", :aggregate_failures do
      sign_in_as(dispatcher)
      post call_acknowledgement_path(call), headers: { "HTTP_REFERER" => calls_url }

      expect(response).to redirect_to(calls_url)
      follow_redirect!
      expect(page.at_css(".flash-notice").text.squish).to eq("SOS of P-12 acknowledged")
      expect(strip).to be_nil
      expect(call.reload).to have_attributes(acknowledged_by: dispatcher, acknowledged_at: Time.current)
    end

    it "takes the strip off every open page at once (DYN-19)" do
      sign_in_as(dispatcher)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      post call_acknowledgement_path(call)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(:sos, hash_including(target: "sos-strips", locals: { calls: [] }))
    end

    it "is refused to the crew", :aggregate_failures do
      sign_in_as(create(:user, :crew, patrol_car: helper))
      post call_acknowledgement_path(call)

      expect(response).to redirect_to(crew_path)
      expect(call.reload.acknowledged_at).to be_nil
    end

    it "is refused without a sign-in", :aggregate_failures do
      post call_acknowledgement_path(call)

      expect(response).to redirect_to(new_session_path)
      expect(call.reload.acknowledged_at).to be_nil
    end

    it "is only for a crew's SOS, and only while the call is active", :aggregate_failures do
      sign_in_as(dispatcher)
      post call_acknowledgement_path(create(:alarm_call, guarded_site: create(:guarded_site)))
      expect(response).to have_http_status(:not_found)

      call.update!(status: :cancelled, closed_at: Time.current)
      post call_acknowledgement_path(call)
      expect(flash[:alert]).to eq("A closed or cancelled call cannot be changed")
    end
  end

  describe "the board (DSP-03, DSP-05)" do
    before { sign_in_as(dispatcher) }

    it "puts the call first, with who asks, its state and the steps of any call", :aggregate_failures do
      create(:alarm_call, guarded_site: create(:guarded_site), priority: :critical, received_at: signalled - 10.minutes)
      get root_path

      card = page.css(".call-card").first
      expect(card["class"].split).to include("sos", "critical")
      expect(card.text.squish).to include("SOS", "Crew of P-12", "Position accuracy 12 m", "Crew's SOS", "From P-12",
                                          "Waiting for a car", "Not acknowledged")
      expect(card.at_css("a[href='#{new_call_dispatch_path(call)}']").text).to eq("Dispatch")
      expect(card.at_css(".call-card-site")["data-board-site-param"]).to eq("map_sos_call_#{call.id}")
      expect(page.at_css(".calls-panel .panel-critical").text.squish).to eq("2 critical")
    end

    it "says on the card who acknowledged the signal" do
      call.acknowledge(dispatcher)
      get root_path

      expect(page.at_css(".call-card.sos").text.squish).to include("Acknowledged 19:49 by Demo Dispatcher")
    end

    it "marks the place of the signal on the map, with the details of the call", :aggregate_failures do
      get root_path

      mark = page.at_css("li#map_sos_call_#{call.id}[data-map-target=site]")
      expect(mark.to_h).to include("data-kind" => "sos", "data-latitude" => "56.95", "data-longitude" => "24.1",
                                   "data-priority" => "critical", "data-letter" => "SOS · P-12",
                                   "data-arrival" => "waiting", "data-label" => "SOS of P-12, waiting for a car")
      expect(mark.at_css(".map-popup").text.squish).to include("Crew of P-12", "Crew's SOS", "Waiting for a car")
      expect(mark.at_css(".map-popup a[href='#{call_path(call)}']").text).to eq("Open the call")
      expect(page.at_css(".map-counts").text.squish).to eq("0 sites · 0 with an active call")
    end

    it "opens the map on the place when asked from the strip" do
      get root_path(sos: call.id)

      expect(page.at_css(".map-view").to_h).to include("data-map-center-value" => "[24.1,56.95]", "data-map-zoom-value" => "15",
                                                       "data-map-open-value" => "map_sos_call_#{call.id}")
    end

    it "marks the car that asks in the cars panel, first of all", :aggregate_failures do
      create(:patrol_car, call_sign: "P-01")
      get root_path
      row = page.css("aside.board-cars li").first
      expect([ row["class"], row.text.squish ]).to match([ "sos", a_string_including("P-12", "SOS", "Signal at 19:47 · not acknowledged") ])

      call.acknowledge(dispatcher)
      get root_path
      expect(page.css("aside.board-cars li").first.text.squish).to include("Signal at 19:47 · acknowledged")
    end

    it "keeps the mark red and named by the place of the signal, whatever the priority and the arrival",
       :aggregate_failures do
      call.update!(priority: :low)
      CallStep.new(call, dispatcher).dispatch(helper)
      CallStep.new(call, create(:user, :crew, patrol_car: helper)).arrive(position: { latitude: "56.96", longitude: "24.1" })
      get root_path

      mark = page.at_css("li#map_sos_call_#{call.id}")
      expect(mark["data-arrival"]).to eq("far")
      expect(mark["data-label"]).to eq("SOS of P-12, arrived farther than 200 m from the place of the signal")
    end

    it "explains the mark in the legend" do
      get root_path

      expect(page.at_css(".map-legend").text.squish).to include("SOS · P-12 Place of a crew's SOS")
    end
  end

  describe "sending a car (UPD-06)" do
    before { sign_in_as(dispatcher) }

    it "offers the free cars but the one that asks, those of its district first", :aggregate_failures do
      helper
      create(:patrol_car, call_sign: "P-21", district: :north)
      get new_call_dispatch_path(call)

      expect(page.css(".car-choice .call-sign").map(&:text)).to eq(%w[ P-21 P-03 ])
      expect(page.at_css(".note").text.squish).to eq("Crew's SOS from P-12, district North")
    end

    it "sends the car as to any call, and that acknowledges the signal", :aggregate_failures do
      post call_dispatch_path(call), params: { patrol_car_id: helper.id }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("P-03 dispatched to Crew of P-12")
      expect(call.reload).to have_attributes(status: "dispatched", patrol_car: helper, acknowledged_by: dispatcher)
    end

    it "refuses the car that asks" do
      post call_dispatch_path(call), params: { patrol_car_id: car.id }

      expect(flash[:alert]).to eq("P-12 raised this call and cannot be sent to it")
    end
  end

  describe "the crew sent to help (CRW-01, CRW-08)" do
    before do
      CallStep.new(call, dispatcher).dispatch(helper)
      sign_in_as(create(:user, :crew, patrol_car: helper))
    end

    it "sees who asks for help and where, and the route to the place", :aggregate_failures do
      get crew_path

      screen = page.at_css(".crew-call")
      expect(page.at_css(".crew [role=status]").text.squish).to eq("Call for P-03: Crew of P-12, critical, dispatched")
      expect(screen.text.squish).to include("Critical", "Crew of P-12", "Crew's SOS", "Signal at 19:47, the last at 19:48",
                                            "Position accuracy 12 m")
      expect(screen.text).not_to include("Keyholder")
      expect(page.at_css(".crew-actions a.route")["href"])
        .to eq("https://www.google.com/maps/dir/?api=1&destination=56.95,24.1&travelmode=driving")
      expect(page.at_css("li#map_sos_call_#{call.id}")["data-kind"]).to eq("sos")
      expect(page.at_css(".map-view")["data-map-center-value"]).to eq("[24.1,56.95]")
    end

    it "takes its steps as for any call, measured from the place of the signal, and closes with an outcome of its own",
       :aggregate_failures do
      post call_acceptance_path(call)
      post call_arrival_path(call), params: { latitude: "56.9501", longitude: "24.1", accuracy: "8" }
      get crew_path
      expect(page.at_css(".crew-call .arrival").text.squish).to include("11 m from the place of the signal")

      get new_call_closing_path(call)
      expect(page.css("select[name=outcome] option").map(&:text)).to eq([ "Choose an outcome", "Help given", "False alarm", "Other" ])
      expect(page.at_css(".note").text.squish).to eq("Crew's SOS from P-12")

      post call_closing_path(call), params: { outcome: "help_given" }
      expect(call.reload).to have_attributes(status: "closed", outcome: "help_given")
    end
  end

  describe "the pages of calls (DSP-02, FLT-01, UPD-05)" do
    before { sign_in_as(dispatcher) }

    def sites = page.css("tbody td[data-label=Site]").map { |cell| cell.text.squish }

    it "show on the call page who asked, the place, the signals and the acknowledgement", :aggregate_failures do
      call.acknowledge(dispatcher)
      get call_path(call)

      details = page.css("dl.details > div").to_h { |row| [ row.at_css("dt").text.squish, row.at_css("dd").text.squish ] }
      expect(page.at_css("h1").text.squish).to eq("Crew's SOS from P-12")
      expect(details).to include("Call" => "Crew's SOS, From P-12", "Raised by" => "P-12",
                                 "Place" => "56.950000, 24.100000 · accuracy 12 m",
                                 "Signals" => "2, the last 03.10.2026 19:48",
                                 "Acknowledged" => "03.10.2026 19:49 by Demo Dispatcher",
                                 "Registered by" => "Traccar Client of P-12")
      expect(details).not_to have_key("Site")
    end

    it "list the call by who asked, find it by the call sign and by its kind, and keep it when ordered by site",
       :aggregate_failures do
      create(:alarm_call, guarded_site: create(:guarded_site, name: "Alpha Shop"))
      get calls_path
      expect(page.at_css("tbody a[href='#{call_path(call)}']").text).to eq("Crew of P-12")
      expect(page.css("select[name=kind] option").map(&:text)).to eq([ "All", "Alarm", "Client call", "Crew's SOS" ])

      get calls_path(q: "p-12")
      expect(sites).to eq([ "Crew of P-12" ])
      get calls_path(kind: "sos")
      expect(sites).to eq([ "Crew of P-12" ])
      get calls_path(sort: "site")
      expect(sites).to eq([ "Alpha Shop", "Crew of P-12" ])
    end

    it "keep it last when ordered by site either way, and out of a district, which is the site's", :aggregate_failures do
      create(:alarm_call, guarded_site: create(:guarded_site, name: "Alpha Shop", district: :east))
      get calls_path(sort: "site", direction: "desc")
      expect(sites).to eq([ "Alpha Shop", "Crew of P-12" ])
      get calls_path(q: "p-12", sort: "car")
      expect(sites).to eq([ "Crew of P-12" ])
      # The district is the site's; a crew's SOS has no site.
      get calls_path(district: "north")
      expect(sites).to eq([])
      expect(page.at_css("#q-hint").text).to eq("Site, contract number, caller or the car of a crew's SOS, 2 characters or more")
    end

    it "open the statistics with a crew's SOS among the calls (CALC-01)", :aggregate_failures do
      get statistics_path
      expect(response).to have_http_status(:ok)

      api_get(api_v1_statistics_path, user: dispatcher)
      expect(response).to have_http_status(:ok)
    end

    it "offer its kind in the clean-up of old calls (DEL-07)" do
      sign_in_as(create(:user, :supervisor))
      get new_call_cleanup_path

      expect(page.css("select[name=kind] option").map(&:text)).to eq([ "All", "Alarm", "Client call", "Crew's SOS" ])
    end

    it "edit the priority and the description only", :aggregate_failures do
      get edit_call_path(call)
      expect(page.at_css(".note").text.squish).to eq("Crew's SOS from P-12, received 03.10.2026 19:47")
      expect(page.css("form.form [name^='call[']").map { |field| field["name"] }).to eq(%w[ call[priority] call[description] ])

      patch call_path(call), params: { call: { description: "Yard of the tyre shop", caller_name: "Example Person",
                                               latitude: "1", raised_by_id: helper.id, signals: "9" } }
      expect(call.reload).to have_attributes(description: "Yard of the tyre shop", caller_name: nil, latitude: 56.95,
                                             raised_by: car, signals: 2)
    end

    it "show the call on the page of the car sent to help, and on that of the car that asked", :aggregate_failures do
      CallStep.new(call, dispatcher).dispatch(helper)
      get patrol_car_path(helper)
      expect(page.css("a[href='#{call_path(call)}']").map(&:text)).to eq([ "Crew of P-12", "Crew of P-12" ])

      get patrol_car_path(car)
      expect(page.css("tbody a[href='#{call_path(call)}']").map(&:text)).to eq([ "Crew of P-12" ])
    end
  end

  describe "the API (API-01, API-02, API-04)" do
    it "gives the call without a site, with who asked, the place and the acknowledgement", :aggregate_failures do
      call.acknowledge(dispatcher)
      body = api_get(api_v1_call_path(call), user: dispatcher)

      expect(body).to include("kind" => "sos", "site" => nil, "priority" => "critical", "registered_by" => nil,
                              "raised_by" => { "id" => car.id, "call_sign" => "P-12" },
                              "place" => { "latitude" => 56.95, "longitude" => 24.1, "accuracy" => 12 }, "signals" => 2,
                              "signalled_at" => (signalled + 1.minute).iso8601,
                              "acknowledged_at" => (signalled + 2.minutes).iso8601, "acknowledged_by" => "Demo Dispatcher")
      expect(api_get(api_v1_calls_path, user: dispatcher, params: { kind: "sos" })["calls"].pluck("id")).to eq([ call.id ])
    end

    it "gives a call at a site none of these", :aggregate_failures do
      site_call = create(:alarm_call, guarded_site: create(:guarded_site))
      body = api_get(api_v1_call_path(site_call), user: dispatcher)

      expect(body).to include("kind" => "alarm", "raised_by" => nil, "place" => nil, "signals" => nil, "signalled_at" => nil,
                              "acknowledged_at" => nil, "acknowledged_by" => nil)
    end

    it "changes its description and its priority only", :aggregate_failures do
      body = api_send(:patch, api_v1_call_path(call), user: dispatcher,
                                                      body: { description: "Yard of the tyre shop", signals: 9, caller_name: "Example Person" })

      expect(response).to have_http_status(:ok)
      expect(body).to include("description" => "Yard of the tyre shop", "signals" => 2, "caller_name" => nil)
    end

    it "refuses to close it with an outcome of another kind of call (API-06)", :aggregate_failures do
      CallStep.new(call, dispatcher).dispatch(helper)
      CallStep.new(call, dispatcher).arrive
      body = api_send(:post, api_v1_call_close_path(call), user: dispatcher, body: { outcome: "fire_confirmed" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("error" => "Outcome is not one of a crew's SOS")
    end
  end
end
