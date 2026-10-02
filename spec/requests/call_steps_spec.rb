require "rails_helper"

RSpec.describe "Call steps" do
  include_context "without the seeded records"

  let(:site) { create(:guarded_site, name: "Warehouse No. 3", district: :north) }
  let(:call) { create(:alarm_call, guarded_site: site) }
  let!(:north_car) { create(:patrol_car, call_sign: "P-2", district: :north) }

  before do
    create(:patrol_car, call_sign: "P-1", district: :centre)
    create(:patrol_car, call_sign: "P-3", district: :north, status: :out_of_service)
    sign_in_as(create(:user))
  end

  def actions
    get root_path
    response.parsed_body.css(".call-card [data-label='Actions'] a, .call-card [data-label='Actions'] button")
            .map { |action| action.text.strip }
  end

  describe "the board" do
    it "offers the next steps of each status (2.10)", :aggregate_failures do
      call
      expect(actions).to eq(%w[Dispatch Cancel Edit])

      CallStep.new(call, call.registered_by).dispatch(north_car)
      expect(actions).to eq(%w[Arrived Cancel Edit])

      CallStep.new(call.reload, call.registered_by).arrive
      expect(actions).to eq(%w[Close Edit])
    end

    it "opens the dialogs in the modal frame and recounts waiting times in the browser (DYN-07, DYN-03)", :aggregate_failures do
      call
      get root_path

      expect(response.parsed_body.at_css("a[href='#{new_call_dispatch_path(call)}']")["data-turbo-frame"]).to eq("modal")
      expect(response.parsed_body.at_css("turbo-frame#modal")).to be_present
      expect(response.parsed_body.at_css("[data-controller~='waiting'] .call-card [data-received-at]")["data-received-at"])
        .to eq(call.received_at.iso8601)
    end
  end

  describe "dispatch (UPD-06, DYN-07)" do
    it "lists the free cars, the site's district first" do
      get new_call_dispatch_path(call), headers: { "Turbo-Frame" => "modal" }

      dialog = response.parsed_body.at_css("turbo-frame#modal dialog")
      expect(dialog.css("form button").map { |button| button.text.squish }).to eq([ "P-2 Skoda Octavia · North", "P-1 Skoda Octavia · Centre" ])
    end

    it "sends the chosen car and returns to the board", :aggregate_failures do
      post call_dispatch_path(call), params: { patrol_car_id: north_car.id }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("P-2 dispatched to Warehouse No. 3")
      expect([ call.reload.status, north_car.reload.status ]).to eq(%w[dispatched dispatched])
    end

    it "refuses a car that is not free (UPD-07)", :aggregate_failures do
      post call_dispatch_path(call), params: { patrol_car_id: PatrolCar.find_by!(call_sign: "P-3").id }

      expect(flash[:alert]).to eq("Car P-3 is not available")
      expect(call.reload).to be_pending
    end
  end

  describe "arrival, closing and cancelling" do
    before { CallStep.new(call, call.registered_by).dispatch(north_car) }

    it "records the arrival with the response time (UPD-08)", :aggregate_failures do
      post call_arrival_path(call)

      expect(flash[:notice]).to start_with("Arrival recorded; response time")
      expect(call.reload).to be_on_scene
    end

    it "asks for an outcome in the closing dialog and closes (UPD-09)", :aggregate_failures do
      post call_arrival_path(call)
      get new_call_closing_path(call)
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty

      post call_closing_path(call), params: { outcome: "false_alarm", note: "Sensor fault" }
      expect(flash[:notice]).to eq("Call closed")
      expect([ call.reload.status, north_car.reload.status ]).to eq(%w[closed available])
    end

    it "refuses closing without an outcome (UPD-09)" do
      post call_arrival_path(call)
      post call_closing_path(call), params: { outcome: "" }

      expect(flash[:alert]).to eq("Choose an outcome to close the call")
    end

    it "cancels with a reason and frees the car (UPD-10)", :aggregate_failures do
      get new_call_cancellation_path(call)
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty

      post call_cancellation_path(call), params: { reason: "Client called back" }
      expect(flash[:notice]).to eq("Call cancelled")
      expect([ call.reload.status, north_car.reload.status ]).to eq(%w[cancelled available])
    end

    it "refuses a step that does not fit the status (UPD-11)" do
      post call_closing_path(call), params: { outcome: "other" }

      expect(flash[:alert]).to eq("Not possible for a dispatched call; possible now: Arrival, Cancel")
    end
  end
end
