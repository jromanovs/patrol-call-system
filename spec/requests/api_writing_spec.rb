require "rails_helper"

RSpec.describe "API writing (API-03, API-04, API-05, API-08)" do
  include_context "without the seeded records"

  let(:dispatcher) { create(:user) }
  let(:supervisor) { create(:user, :supervisor) }
  let(:site) { create(:guarded_site, name: "Office Centre") }

  # The messages the form would show for the same record (ADD-02).
  def form_messages(record, field) = record.tap(&:validate).errors.full_messages_for(field)

  describe "sites" do
    let(:fields) do
      { contract_number: "C-00500", name: "API Office", client_name: "Example Api Ltd", address_id: create(:address).id,
        site_type: "office", district: "centre", keyholder_phone: "+37100000500", contract_start_date: "2026-10-01",
        access_notes: "Key at the guard post" }
    end

    it "creates a site and answers 201 with it (API-03)", :aggregate_failures do
      body = api_send(:post, api_v1_sites_path, user: dispatcher, body: fields)

      expect(response).to have_http_status(:created)
      expect(body).to include("contract_number" => "C-00500", "name" => "API Office", "access_notes" => "Key at the guard post")
      expect(GuardedSite.find(body["id"]).client_name).to eq("Example Api Ltd")
    end

    it "answers 422 with the messages of the form per field (API-03, ADD-02)", :aggregate_failures do
      body = api_send(:post, api_v1_sites_path, user: dispatcher, body: fields.merge(contract_number: "X", address_id: nil))

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["errors"]).to include(
        "contract_number" => form_messages(GuardedSite.new(contract_number: "X"), :contract_number),
        "address_id" => form_messages(GuardedSite.new, :address)
      )
      expect(GuardedSite.count).to eq(0)
    end

    it "changes a site and answers 200 with it (API-04)", :aggregate_failures do
      body = api_send(:patch, api_v1_site_path(site), user: dispatcher, body: { name: "Office West" })

      expect(response).to have_http_status(:ok)
      expect([ body["name"], site.reload.name ]).to eq([ "Office West", "Office West" ])
    end

    it "deletes a site without calls and keeps one with calls, giving the reason (API-05, BR-9)", :aggregate_failures do
      busy = create(:guarded_site)
      create(:alarm_call, guarded_site: busy)

      expect(api_send(:delete, api_v1_site_path(site), user: dispatcher)).to be_nil
      expect(response).to have_http_status(:no_content)
      expect(api_send(:delete, api_v1_site_path(busy), user: dispatcher))
        .to eq("error" => "Site has 1 call and cannot be deleted; suspend the contract instead")
      expect(response).to have_http_status(:unprocessable_content)
      expect(GuardedSite.pluck(:id)).to eq([ busy.id ])
    end
  end

  describe "patrol cars" do
    let(:car) { create(:patrol_car, call_sign: "P-40") }

    it "creates, changes and deletes a car (API-03, API-04, API-05)", :aggregate_failures do
      body = api_send(:post, api_v1_patrol_cars_path, user: dispatcher,
                                                      body: { call_sign: "P-41", plate_number: "ZZ-0041", model: "Skoda Octavia",
                                                              crew_size: 2, district: "east" })
      expect([ response.status, body["call_sign"] ]).to eq([ 201, "P-41" ])

      expect(api_send(:patch, api_v1_patrol_car_path(car), user: dispatcher, body: { status: "out_of_service" })["status"])
        .to eq("out_of_service")

      api_send(:delete, api_v1_patrol_car_path(body["id"]), user: dispatcher)
      expect([ response.status, PatrolCar.pluck(:call_sign) ]).to eq([ 204, [ "P-40" ] ])
    end

    it "keeps a status that only a call sets (BR-5)" do
      expect(api_send(:patch, api_v1_patrol_car_path(car), user: dispatcher, body: { status: "dispatched" })["status"])
        .to eq("available")
    end

    it "does not free by hand a car that is on a call (BR-5)", :aggregate_failures do
      car.update_column(:status, PatrolCar.statuses[:dispatched])

      expect(api_send(:patch, api_v1_patrol_car_path(car), user: dispatcher, body: { status: "available" })["status"])
        .to eq("dispatched")
      expect(car.reload).to be_dispatched
    end

    it "keeps a car with calls, giving the reason (API-05, BR-9)", :aggregate_failures do
      create(:alarm_call).update_columns(status: Call.statuses[:closed], patrol_car_id: car.id)

      expect(api_send(:delete, api_v1_patrol_car_path(car), user: dispatcher))
        .to eq("error" => "Car has 1 call and cannot be deleted; put it out of service instead")
      expect([ response.status, PatrolCar.exists?(car.id) ]).to eq([ 422, true ])
    end

    it "keeps a car whose positions are kept, giving the reason (API-05, BR-20)", :aggregate_failures do
      create(:car_position, patrol_car: car, created_at: Time.zone.local(2026, 10, 3, 13, 4))

      expect(api_send(:delete, api_v1_patrol_car_path(car), user: dispatcher))
        .to eq("error" => "Car has positions kept since 03.10.2026 and cannot be deleted; put it out of service instead")
      expect([ response.status, CarPosition.count ]).to eq([ 422, 1 ])
    end
  end

  describe "calls" do
    it "registers an alarm call for the key's user, with the priority of its type, and refreshes the boards " \
       "(API-03, BR-2, API-08)", :aggregate_failures do
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)

      body = api_send(:post, api_v1_calls_path, user: dispatcher,
                                                body: { kind: "alarm", guarded_site_id: site.id, alarm_type: "fire", sensor_zone: 3 })

      expect(response).to have_http_status(:created)
      expect(body).to include("kind" => "alarm", "priority" => "critical", "status" => "pending",
                              "registered_by" => dispatcher.name)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:board, any_args)
    end

    it "takes from the body only the fields of the form, never the steps or the author (API-03)", :aggregate_failures do
      car = create(:patrol_car)
      body = api_send(:post, api_v1_calls_path, user: dispatcher,
                                                body: { kind: "alarm", guarded_site_id: site.id, alarm_type: "fire", sensor_zone: 3,
                                                        status: "closed", patrol_car_id: car.id, outcome: "false_alarm",
                                                        dispatched_at: "2026-10-01T09:00:00+03:00", registered_by_id: supervisor.id,
                                                        type: "ClientCall" })

      expect(body).to include("kind" => "alarm", "status" => "pending", "car" => nil, "outcome" => nil, "dispatched_at" => nil,
                              "registered_by" => dispatcher.name)
    end

    it "registers a client call (API-03)" do
      body = api_send(:post, api_v1_calls_path, user: dispatcher,
                                                body: { kind: "client", guarded_site_id: site.id, caller_name: "Example Person",
                                                        caller_phone: "+37100000005" })

      expect(body).to include("kind" => "client", "priority" => "normal", "caller_name" => "Example Person")
    end

    it "refuses a call for a suspended contract with the message of the form (API-03, BR-1)", :aggregate_failures do
      suspended = create(:guarded_site, :suspended)
      body = api_send(:post, api_v1_calls_path, user: dispatcher,
                                                body: { kind: "alarm", guarded_site_id: suspended.id, alarm_type: "fire", sensor_zone: 3 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["errors"]["base"])
        .to eq([ "Contract #{suspended.contract_number} is suspended — call cannot be registered" ])
    end

    it "changes an active call and refuses a closed one (API-04, BR-7)", :aggregate_failures do
      active = create(:alarm_call, guarded_site: site)
      closed = create(:alarm_call, guarded_site: site).tap { |call| call.update_column(:status, Call.statuses[:closed]) }

      expect(api_send(:patch, api_v1_call_path(active), user: dispatcher, body: { priority: "low" })["priority"]).to eq("low")
      expect(api_send(:patch, api_v1_call_path(closed), user: dispatcher, body: { priority: "low" }))
        .to eq("errors" => { "base" => [ "A closed or cancelled call cannot be changed" ] })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "keeps a finished call within the period it is kept for, giving the day (API-05, BR-23)", :aggregate_failures do
      travel_to(Time.zone.local(2026, 10, 4, 12, 0))
      closed = create(:alarm_call, guarded_site: site, received_at: Time.zone.local(2026, 3, 14, 9, 12))
      closed.update_column(:status, Call.statuses[:closed])

      expect(api_send(:delete, api_v1_call_path(closed), user: supervisor))
        .to eq("error" => "Call is kept until 14.03.2028 and cannot be deleted")
      expect([ response.status, Call.exists?(closed.id) ]).to eq([ 422, true ])
    end

    it "lets a supervisor delete a finished call, never an active one (API-05, BR-8)", :aggregate_failures do
      active = create(:alarm_call, guarded_site: site)
      closed = create(:alarm_call, guarded_site: site, received_at: 25.months.ago)
               .tap { |call| call.update_column(:status, Call.statuses[:closed]) }

      api_send(:delete, api_v1_call_path(closed), user: supervisor)
      expect(response).to have_http_status(:no_content)
      expect(api_send(:delete, api_v1_call_path(active), user: supervisor))
        .to eq("error" => "Active call cannot be deleted; cancel or close it first")
      expect(Call.pluck(:id)).to eq([ active.id ])
    end

    it "refuses a dispatcher deleting a call (BR-14, AUTH-07)", :aggregate_failures do
      closed = create(:alarm_call, guarded_site: site).tap { |call| call.update_column(:status, Call.statuses[:closed]) }

      expect(api_send(:delete, api_v1_call_path(closed), user: dispatcher)).to eq("error" => "Not allowed for your role")
      expect(response).to have_http_status(:forbidden)
      expect(Call.exists?(closed.id)).to be(true)
    end
  end

  it "answers 400 with a JSON message to a body that is not JSON (4.2)", :aggregate_failures do
    body = api_send(:post, api_v1_sites_path, user: dispatcher, body: "{ not json")

    expect(response).to have_http_status(:bad_request)
    expect(body).to eq("error" => "The request body is not valid JSON")
  end
end
