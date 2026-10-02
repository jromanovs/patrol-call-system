require "rails_helper"

RSpec.describe "The crew (CRW-01 … CRW-03, DYN-15)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let(:crew) { create(:user, :crew, patrol_car: car) }
  let(:dispatcher) { create(:user) }
  let(:site) do
    create(:guarded_site, name: "Demo Office 1", keyholder_phone: "+37100000011", access_notes: "Key at the reception",
                          address: create(:address, full_address: "Jēkaba iela 11, Rīga, LV-1050"))
  end
  let(:call) { create(:alarm_call, guarded_site: site, priority: :critical, alarm_type: :panic, sensor_zone: 2) }

  before do
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: true))
  end

  def page = response.parsed_body

  def dispatched = call.tap { CallStep.new(call, dispatcher).dispatch(car) }

  describe "the crew screen (CRW-01)" do
    before { sign_in_as(crew) }

    it "opens in place of the board" do
      get root_path

      expect(response).to redirect_to(crew_path)
    end

    it "shows the car's call with what the crew needs on the way", :aggregate_failures do
      dispatched
      get crew_path

      screen = page.at_css(".crew-call")
      expect(page.at_css(".crew-car").text.squish).to eq("P-12 Dispatched")
      expect(page.at_css(".crew [role=status]").text.squish).to eq("Call for P-12: Demo Office 1, critical, dispatched")
      expect(screen.text.squish).to include("Critical", "Demo Office 1", "Jēkaba iela 11, Rīga, LV-1050", "since the call",
                                            site.contract_number, "Alarm: panic", "Zone 2", "Key at the reception",
                                            "P-12 on the way")
      expect(screen.at_css("a[href='tel:+37100000011']").text).to eq("+37100000011")
      expect(page.css("form[action='#{call_arrival_path(call)}'] button").map(&:text)).to eq([ "Arrived" ])
      expect(page.at_css("a[href='#{new_call_closing_path(call)}']")).to be_nil
      expect(page.at_css(".map-small [data-map-target=site]")[:id]).to eq("map_guarded_site_#{site.id}")
    end

    it "offers Close once the car is on site", :aggregate_failures do
      CallStep.new(dispatched, dispatcher).arrive
      get crew_path

      expect(page.at_css("a[href='#{new_call_closing_path(call)}']")["data-turbo-frame"]).to eq("modal")
      expect(page.at_css("form[action='#{call_arrival_path(call)}']")).to be_nil
    end

    it "says when the car has no call", :aggregate_failures do
      get crew_path

      expect(page.at_css(".crew-idle").text.squish)
        .to include("No call for P-12", "and as a notice on this phone when notices are on")
      expect(page.at_css(".crew [role=status]").text.squish).to eq("No call for P-12")
    end

    it "shows on its map only its own call, without links to pages the crew may not open", :aggregate_failures do
      dispatched
      # More urgent on the board than the crew's own: as urgent, and older.
      other = create(:client_call, guarded_site: site, priority: :critical, caller_name: "Other Caller",
                                   received_at: 10.minutes.ago)
      CallStep.new(other, dispatcher).dispatch(create(:patrol_car))
      get crew_path

      marker = page.at_css(".map-small [data-map-target=site]")
      expect(marker["data-priority"]).to eq("critical")
      expect(marker.text).not_to include("Other Caller")
      expect(marker.css("a").map { |link| link[:href] }).to eq([])
    end

    it "lets the crew sign out" do
      delete session_path

      expect(response).to redirect_to(new_session_path)
    end

    it "follows every change of the car's call without a reload (DYN-15)", :aggregate_failures do
      get crew_path

      expect(page.at_css("turbo-cable-stream-source")["signed-stream-name"])
        .to eq(Turbo::StreamsChannel.signed_stream_name(:board))
      expect(page.at_css("meta[name=turbo-refresh-method]")[:content]).to eq("morph")
    end

    it "has the notice switch, kept through every refresh (CRW-04, CRW-05, DYN-16)", :aggregate_failures do
      get crew_path

      switch = page.at_css("#crew-notices[data-controller=notices]")
      expect(switch.key?("data-turbo-permanent")).to be(true)
      expect(switch["data-notices-key-value"]).to eq(CrewNotice.keys[:public_key])
      expect(switch["data-notices-url-value"]).to eq(push_subscription_path)
      expect(switch["data-notices-worker-value"]).to eq(pwa_service_worker_path(format: :js))
      expect(switch.css("[data-notices-target=state]").to_h { |state| [ state["data-state"], state.text.squish ] }).to eq(
        "on" => "Notices are on for this phone", "off" => "Notices are off for this phone",
        "blocked" => "Notices are blocked on this phone; allow them in the phone's settings",
        "unavailable" => "This browser cannot show notices. On an iPhone, add the application to the Home Screen " \
                         "and open it from there")
      expect(switch.css("button").map { |button| [ button.text.squish, button["data-action"] ] })
        .to eq([ [ "Turn on notices", "notices#turnOn" ], [ "Turn off notices", "notices#turnOff" ] ])
      expect(switch.css("[data-notices-target], button").map { |part| part.key?("hidden") }).to all(be(true))
    end

    it "offers the crew only its screen in the menu, and no API key", :aggregate_failures do
      get crew_path

      expect(page.css("nav[aria-label='Main'] ul a").map { |link| [ link.text, link[:href] ] }).to eq([ [ "My car", crew_path ] ])
      expect(page.at_css("header a[href='#{api_key_path}']")).to be_nil
    end
  end

  describe "the crew's steps (CRW-02)" do
    before { sign_in_as(crew) }

    it "records the arrival of its car and returns to its screen", :aggregate_failures do
      post call_arrival_path(dispatched)

      expect(response).to redirect_to(crew_path)
      expect([ call.reload.status, car.reload.status ]).to eq(%w[ on_scene on_scene ])
    end

    it "closes its car's call with an outcome", :aggregate_failures do
      CallStep.new(dispatched, dispatcher).arrive
      post call_closing_path(call), params: { outcome: "false_alarm", note: "Window closed" }

      expect(response).to redirect_to(crew_path)
      expect([ call.reload.status, call.outcome, car.reload.status ]).to eq(%w[ closed false_alarm available ])
    end
  end

  describe "the crew outside its screen (CRW-03)" do
    before { sign_in_as(crew) }

    it "leads every other page to the crew screen", :aggregate_failures do
      [ calls_path, guarded_sites_path, patrol_cars_path, statistics_path, users_path, api_key_path,
        addresses_path(q: "Jēkaba"), call_path(call), new_call_path, edit_call_path(call), map_path,
        new_call_cleanup_path ].each do |path|
        get path
        expect(response).to redirect_to(crew_path)
      end
    end

    it "refuses the steps of another car's call and leaves it as it was", :aggregate_failures do
      other = create(:alarm_call, guarded_site: site)
      CallStep.new(other, dispatcher).dispatch(create(:patrol_car))

      post call_arrival_path(other)
      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(other.reload.status).to eq("dispatched")
    end

    it "opens no closing dialog for another car's call", :aggregate_failures do
      other = create(:alarm_call, guarded_site: site)
      CallStep.new(other, dispatcher).dispatch(create(:patrol_car))

      get new_call_closing_path(other), headers: { "Turbo-Frame" => "modal" }

      expect([ response, flash[:alert] ]).to match([ redirect_to(crew_path), "Not allowed for your role" ])
      expect(response.body).not_to include("Close the call")
    end

    it "refuses to cancel its own car's call, with the reason", :aggregate_failures do
      post call_cancellation_path(dispatched), params: { reason: "Test" }

      expect([ response, flash[:alert] ]).to match([ redirect_to(crew_path), "Not allowed for your role" ])
      expect(call.reload.status).to eq("dispatched")
    end

    it "refuses to dispatch a free car, with the reason", :aggregate_failures do
      post call_dispatch_path(call), params: { patrol_car_id: create(:patrol_car).id }

      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(call.reload.status).to eq("pending")
    end
  end

  describe "the crew through the API (CRW-03)" do
    it "may record its own car's arrival and closing and nothing else", :aggregate_failures do
      expect(api_send(:post, api_v1_call_arrival_path(dispatched), user: crew)).to include("status" => "on_scene")
      expect(api_send(:post, api_v1_call_close_path(call), user: crew, body: { outcome: "other" }))
        .to include("status" => "closed")

      other = create(:alarm_call, guarded_site: site)
      CallStep.new(other, dispatcher).dispatch(create(:patrol_car))
      api_send(:post, api_v1_call_arrival_path(other), user: crew)
      expect(response).to have_http_status(:forbidden)

      api_send(:get, api_v1_calls_path, user: crew)
      expect(response).to have_http_status(:forbidden)
      api_send(:get, api_v1_addresses_path(q: "Jēkaba"), user: crew)
      expect(response).to have_http_status(:forbidden)
      api_send(:post, api_v1_call_cancel_path(call), user: crew, body: { reason: "Test" })
      expect(response).to have_http_status(:forbidden)
    end
  end
end
