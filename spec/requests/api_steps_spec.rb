require "rails_helper"

RSpec.describe "API steps of a call (API-06, API-08)" do
  include_context "without the seeded records"

  let(:dispatcher) { create(:user) }
  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let(:call) { create(:alarm_call) }

  def step(path, body = {}) = api_send(:post, path, user: dispatcher, body:)

  it "dispatches a free car, records the arrival and closes with an outcome; the car follows", :aggregate_failures do
    expect(step(api_v1_call_dispatch_path(call), patrol_car_id: car.id))
      .to include("status" => "dispatched", "car" => { "id" => car.id, "call_sign" => "P-12" },
                  "dispatched_by" => dispatcher.name)
    expect(car.reload).to be_dispatched

    expect(step(api_v1_call_arrival_path(call))).to include("status" => "on_scene")
    expect(car.reload).to be_on_scene

    body = step(api_v1_call_close_path(call), outcome: "false_alarm", note: "Window left open")
    expect(body).to include("status" => "closed", "outcome" => "false_alarm")
    expect(body["description"]).to include("Closing note: Window left open")
    expect([ response.status, car.reload.status ]).to eq([ 200, "available" ])
  end

  it "answers 409 when the car is not available (UPD-07, STO-03)", :aggregate_failures do
    car.update_column(:status, PatrolCar.statuses[:out_of_service])

    expect(step(api_v1_call_dispatch_path(call), patrol_car_id: car.id)).to eq("error" => "Car P-12 is not available")
    expect(response).to have_http_status(:conflict)
    expect(call.reload).to be_pending
  end

  it "answers 422 with the steps possible now for a step out of order (UPD-11)", :aggregate_failures do
    expect(step(api_v1_call_arrival_path(call)))
      .to eq("error" => "Not possible for a pending call; possible now: Dispatch, Cancel")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "answers 422 when a call is closed without an outcome (UPD-09)", :aggregate_failures do
    step(api_v1_call_dispatch_path(call), patrol_car_id: car.id)
    step(api_v1_call_arrival_path(call))

    expect(step(api_v1_call_close_path(call))).to eq("error" => "Choose an outcome to close the call")
    expect([ response.status, call.reload.status ]).to eq([ 422, "on_scene" ])
  end

  it "cancels a dispatched call with a reason and frees the car (UPD-10)", :aggregate_failures do
    step(api_v1_call_dispatch_path(call), patrol_car_id: car.id)

    body = step(api_v1_call_cancel_path(call), reason: "Client called back")
    expect(body).to include("status" => "cancelled", "outcome" => nil)
    expect(body["description"]).to include("Cancelled: Client called back")
    expect(car.reload).to be_available
  end

  it "refuses every step of a finished call (BR-7)", :aggregate_failures do
    call.update_column(:status, Call.statuses[:closed])

    expect(step(api_v1_call_cancel_path(call))).to eq("error" => "The call is closed; no further steps")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "needs the car of a dispatch, and an existing one", :aggregate_failures do
    expect(step(api_v1_call_dispatch_path(call))).to eq("error" => "Missing field: patrol_car_id")
    expect(response).to have_http_status(:bad_request)
    expect(step(api_v1_call_dispatch_path(call), patrol_car_id: 0)).to eq("error" => "Not found")
    expect(response).to have_http_status(:not_found)
  end

  it "refreshes the open boards after a dispatch, for the call and for the car (API-08)" do
    call
    car
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)

    step(api_v1_call_dispatch_path(call), patrol_car_id: car.id)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:board, any_args).twice
  end

  it "answers 409 for a car already on another call, caught by the database at the latest (STO-03)",
     :aggregate_failures do
    create(:alarm_call).update_columns(status: Call.statuses[:dispatched], patrol_car_id: car.id)

    expect(step(api_v1_call_dispatch_path(call), patrol_car_id: car.id)).to eq("error" => "Car P-12 is not available")
    expect([ response.status, call.reload.status ]).to eq([ 409, "pending" ])
  end
end
