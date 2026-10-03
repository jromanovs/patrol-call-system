require "rails_helper"

RSpec.describe "Further cars of a call (BR-22, UPD-14 … UPD-16, CRW-12)" do
  include_context "without the seeded records"

  let(:dispatcher) { create(:user, name: "Demo Dispatcher") }
  let(:first) { create(:patrol_car, call_sign: "P-03") }
  let(:further) { create(:patrol_car, call_sign: "P-15") }
  let(:site) do
    create(:guarded_site, name: "Demo Shop 10", district: :north,
                          address: create(:address, full_address: "Jēkaba iela 11, Rīga, LV-1050"))
  end
  let(:call) { create(:alarm_call, guarded_site: site, received_at: now - 3.minutes) }

  before do
    travel_to(now)
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: true))
    CallStep.new(call, dispatcher).dispatch(first)
  end

  after { travel_back }

  def now = Time.zone.local(2026, 10, 3, 19, 50)

  def page = response.parsed_body

  def send_further = BackupStep.new(call, dispatcher).send_car(further)

  def lines = page.css(".call-card .backup").map { |line| line.text.squish }

  describe "sending (UPD-14)" do
    before { sign_in_as(dispatcher) }

    it "is offered on the card of a call that has its car, of any kind, not on one that waits for it", :aggregate_failures do
      waiting = create(:client_call, guarded_site: site)
      get root_path

      link = page.at_css("##{ActionView::RecordIdentifier.dom_id(call)} a[href='#{new_call_backup_path(call)}']")
      expect([ link.text.squish, link["data-turbo-frame"] ]).to eq([ "Send another car", "modal" ])
      expect(page.at_css("a[href='#{new_call_backup_path(waiting)}']")).to be_nil
    end

    it "offers the free cars, those of the call's district first, and names the cars sent already", :aggregate_failures do
      send_further
      create(:patrol_car, call_sign: "P-07", district: :east)
      create(:patrol_car, call_sign: "P-21", district: :north)
      get new_call_backup_path(call)

      expect(page.at_css("#dialog-title").text).to eq("Send another car")
      expect(page.css(".car-choice .call-sign").map(&:text)).to eq(%w[ P-21 P-07 ])
      expect(page.at_css(".note").text.squish).to eq("Alarm: intrusion at Demo Shop 10, district North. Sent already: P-03, P-15.")
    end

    it "sends the car chosen and says so", :aggregate_failures do
      post call_backups_path(call), params: { patrol_car_id: further.id }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("P-15 sent to Demo Shop 10 as a further car")
      expect(call.backups.sole).to have_attributes(patrol_car: further, sent_by: dispatcher)
    end

    it "does not open the choice of a further car for a call that has no car", :aggregate_failures do
      waiting = create(:client_call, guarded_site: site)
      get new_call_backup_path(waiting)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("The call has no car yet; dispatch one first")
    end

    it "says why a car could not be sent" do
      post call_backups_path(call), params: { patrol_car_id: first.id }

      expect(flash[:alert]).to eq("Car P-03 is not available")
    end

    it "is not for the crew", :aggregate_failures do
      sign_in_as(create(:user, :crew, patrol_car: first))
      post call_backups_path(call), params: { patrol_car_id: further.id }

      expect(response).to redirect_to(crew_path)
      expect(Backup.count).to eq(0)
    end
  end

  describe "the board (DSP-03)" do
    before { sign_in_as(dispatcher) }

    it "gives every further car its own line of state", :aggregate_failures do
      backup = send_further
      get root_path
      expect(lines).to eq([ "P-15 sent 19:50 · not accepted" ])

      travel_to(now + 1.minute)
      BackupStep.new(call, dispatcher).accept(backup)
      get root_path
      expect(lines).to eq([ "P-15 accepted 19:51 · on the way" ])

      travel_to(now + 6.minutes)
      BackupStep.new(call, dispatcher).arrive(backup)
      get root_path
      expect(lines).to eq([ "P-15 on site since 19:56 · by radio, no position" ])
    end

    it "warns when a further car marked Arrived far from the site (CRW-09)", :aggregate_failures do
      crew = create(:user, :crew, patrol_car: further)
      away = { latitude: (site.address.latitude + 0.02).to_s, longitude: site.address.longitude.to_s, accuracy: "9" }
      BackupStep.new(call, crew).arrive(send_further, position: away)
      get root_path

      line = page.at_css(".call-card .backup")
      expect([ line["data-arrival"], line.text.squish ]).to eq([ "far", "P-15 marked Arrived 2.2 km from the site · accuracy 9 m" ])

      get call_path(call)
      expect(page.at_css(".cars-sent .arrival[data-arrival=far]").text.squish).to include("2.2 km from the site")
    end

    it "puts the steps of each car beside its own line, and the steps of the call below", :aggregate_failures do
      backup = send_further
      get root_path

      blocks = page.css(".call-card .car-state")
      expect(blocks.map { |block| block.at_css(".arrival").text.squish })
        .to eq([ "P-03 sent 19:50 · not accepted · 0 min", "P-15 sent 19:50 · not accepted" ])
      expect(blocks.map { |block| block.css("button").map { |button| button.text.squish } })
        .to eq([ %w[ Accepted Arrived ], %w[ Accepted Arrived Release ] ])
      expect(blocks.map { |block| block.css("form").map { |form| form["action"] } })
        .to eq([ [ call_acceptance_path(call), call_arrival_path(call) ],
                 [ accept_call_backup_path(call, backup), arrive_call_backup_path(call, backup),
                   release_call_backup_path(call, backup) ] ])
      expect(blocks.last.text.squish).to include("further car")
      expect(page.css(".call-card > .row-actions a, .call-card > .row-actions button").map { |one| one.text.squish })
        .to eq([ "Send another car", "Cancel", "Edit" ])
    end

    it "offers each car only the steps it has left" do
      backup = send_further
      CallStep.new(call, dispatcher).accept
      BackupStep.new(call, dispatcher).arrive(backup)
      get root_path

      expect(page.css(".call-card .car-state").map { |block| block.css("button").map { |button| button.text.squish } })
        .to eq([ %w[ Arrived ], %w[ Release ] ])
    end

    it "drops the line of a released car" do
      BackupStep.new(call, dispatcher).release(send_further)
      get root_path

      expect(lines).to eq([])
    end
  end

  describe "the call page (DSP-02)" do
    before { sign_in_as(dispatcher) }

    def rows = page.css(".cars-sent tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }

    it "lists the cars sent with the time of every step, the first car first", :aggregate_failures do
      backup = send_further
      travel_to(now + 6.minutes)
      BackupStep.new(call, create(:user, :crew, patrol_car: further, name: "Demo Crew"))
                .arrive(backup, position: { latitude: site.address.latitude.to_s, longitude: site.address.longitude.to_s })
      get call_path(call)

      expect(page.css(".cars-sent thead th").map { |cell| cell.text.squish })
        .to eq([ "Car", "Sent", "Accepted", "Arrived", "Free again", "Sent by", "Actions" ])
      expect(rows.map { |row| row.first(6) }).to eq([
        [ "P-03 first car", "19:50", "—", "—", "—", "Demo Dispatcher" ],
        [ "P-15", "19:50", "19:56", "19:56 · 0 m from the site", "—", "Demo Dispatcher" ]
      ])
    end

    it "lets the dispatcher record the steps a crew told by radio, and release the car", :aggregate_failures do
      backup = send_further
      get call_path(call)
      expect(page.css(".cars-sent tbody tr").last.css("button").map { |button| button.text.squish })
        .to eq(%w[ Accepted Arrived Release ])

      post accept_call_backup_path(call, backup), headers: { "HTTP_REFERER" => call_url(call) }
      expect(response).to redirect_to(call_url(call))
      post arrive_call_backup_path(call, backup)
      expect(backup.reload).to have_attributes(state: "on-site")

      post release_call_backup_path(call, backup)
      expect(flash[:notice]).to eq("P-15 released")
      expect([ backup.reload.released_at, further.reload.status ]).to eq([ Time.current, "available" ])
      get call_path(call)
      expect(rows.last[4]).to eq("19:50")
      expect(page.css(".cars-sent tbody tr").last.css("button")).to be_empty
    end

    it "shows the response time of a call that only a further car reached" do
      travel_to(now + 3.minutes)
      BackupStep.new(call, dispatcher).arrive(send_further)
      get call_path(call)

      details = page.css("dl.details > div").to_h { |row| [ row.at_css("dt").text.squish, row.at_css("dd").text.squish ] }
      expect(details).to include("Response time" => "6.0 min, to the first car that arrived")
    end

    it "shows no such table for a call with its one car" do
      get call_path(call)

      expect(page.at_css(".cars-sent")).to be_nil
    end
  end

  describe "the crew of a further car (CRW-12)" do
    before do
      send_further
      sign_in_as(create(:user, :crew, patrol_car: further))
    end

    def crew = further.crew.sole

    def backup = call.backups.find_by!(patrol_car: further)

    it "sees the call on its screen, with the car sent before it, and its own steps only", :aggregate_failures do
      get crew_path

      expect(page.at_css(".crew-car").text.squish).to eq("P-15 Dispatched")
      expect(page.at_css(".crew [role=status]").text.squish).to eq("Call for P-15: Demo Shop 10, high, sent as a further car")
      expect(page.at_css(".crew-call").text.squish).to include("Demo Shop 10", "Jēkaba iela 11", "Sent with you: P-03")
      expect(page.at_css(".crew-actions form[action='#{accept_call_backup_path(call, backup)}'] button").text.squish)
        .to eq("Accept the call")
      expect(page.at_css(".crew-actions a.route")).not_to be_nil
    end

    it "accepts, then marks Arrived with where its phone is, and cannot close the call", :aggregate_failures do
      post accept_call_backup_path(call, backup)
      expect(response).to redirect_to(crew_path)
      get crew_path
      form = page.at_css(".crew-actions form[action='#{arrive_call_backup_path(call, backup)}']")
      expect([ form.at_css("button").text.squish, form["data-controller"] ]).to eq(%w[ Arrived position ])

      post arrive_call_backup_path(call, backup), params: { latitude: site.address.latitude.to_s,
                                                            longitude: site.address.longitude.to_s }
      expect(backup.reload.arrival_position).to have_attributes(user: crew, distance: 0)
      # The call's own car arrives too: the call can now be closed, by its crew or the dispatcher only.
      CallStep.new(call, dispatcher).arrive
      get crew_path
      expect(page.at_css(".crew-actions").text.squish)
        .to eq("On site as a further car. This car is free again when the dispatcher releases it or the call ends.")
      expect([ page.at_css("a[href='#{new_call_closing_path(call)}']"), page.at_css(".crew-photos") ]).to eq([ nil, nil ])

      post call_closing_path(call), params: { outcome: "false_alarm" }
      expect(call.reload.status).to eq("on_scene")
    end

    it "takes no step of another further car, nor releases its own", :aggregate_failures do
      other = BackupStep.new(call, dispatcher).send_car(create(:patrol_car, call_sign: "P-21"))
      post accept_call_backup_path(call, other)
      post release_call_backup_path(call, backup)

      expect([ other.reload.accepted_at, backup.reload.released_at ]).to eq([ nil, nil ])
    end

    it "has no call once released" do
      BackupStep.new(call, dispatcher).release(backup)
      get crew_path

      expect(page.at_css(".crew-idle").text).to include("No call for P-15")
    end

    it "is told of the call on its phones (CRW-04)" do
      phone = create(:push_subscription, user: crew)
      sent = []
      allow(WebPush).to receive(:payload_send) { |**notice| sent << notice[:endpoint] }
      CrewNotice.new(call, car: further).deliver
      expect(sent).to eq([ phone.endpoint ])

      # Once it has accepted, or is released, there is nothing to tell.
      BackupStep.new(call, dispatcher).accept(backup)
      CrewNotice.new(call, car: further).deliver
      expect(sent.size).to eq(1)
    end
  end

  describe "elsewhere" do
    it "tells the crew that asked by an SOS of every car sent to it (CRW-11)" do
      asking = create(:patrol_car, call_sign: "P-12")
      sos = create(:sos_call, raised_by: asking)
      CallStep.new(sos, dispatcher).dispatch(create(:patrol_car, call_sign: "P-07"))
      backup = BackupStep.new(sos, dispatcher).send_car(further)
      travel_to(now + 6.minutes)
      BackupStep.new(sos, dispatcher).arrive(backup)
      sign_in_as(create(:user, :crew, patrol_car: asking))
      get crew_path

      expect(page.at_css(".crew-sos-state").text.squish)
        .to eq("P-07 and P-15 are sent to you P-07 dispatched at 19:50 P-15 sent at 19:50 · accepted at 19:56 · arrived at 19:56")
    end

    it "never offers the car that asked by an SOS as a further car of its own call" do
      asking = create(:patrol_car, call_sign: "P-12")
      sos = create(:sos_call, raised_by: asking)
      CallStep.new(sos, dispatcher).dispatch(create(:patrol_car, call_sign: "P-07"))
      further
      sign_in_as(dispatcher)
      get new_call_backup_path(sos)

      expect(page.css(".car-choice .call-sign").map(&:text)).to eq(%w[ P-15 ])
    end

    it "counts the further cars in the list of calls and gives them in the API", :aggregate_failures do
      send_further
      sign_in_as(dispatcher)
      get calls_path
      expect(page.at_css("tbody td[data-label=Car]").text.squish).to eq("P-03 +1")

      body = api_get(api_v1_call_path(call), user: dispatcher)
      expect(body["backups"]).to eq([ { "car" => { "id" => further.id, "call_sign" => "P-15" }, "sent_at" => now.iso8601,
                                        "accepted_at" => nil, "arrived_at" => nil, "released_at" => nil } ])
    end

    it "shows the call as the current one on the page of a further car" do
      send_further
      sign_in_as(dispatcher)
      get patrol_car_path(further)

      expect(page.at_css("dl.details").text.squish).to include("Current call Demo Shop 10")
    end
  end
end
