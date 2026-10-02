require "rails_helper"

RSpec.describe "API statistics (API-07)" do
  include_context "without the seeded records"

  let(:user) { create(:user) }
  let(:site) { create(:guarded_site, name: "Warehouse No. 3") }
  let(:car) { create(:patrol_car, call_sign: "P-12") }

  def received(status, arrival: nil, outcome: nil)
    received_at = Time.zone.local(2026, 9, 10, 9, 0)
    create(:alarm_call, guarded_site: site, priority: :critical, received_at:).tap do |call|
      call.update_columns(status: Call.statuses.fetch(status), outcome: outcome && Call.outcomes.fetch(outcome),
                          patrol_car_id: arrival && car.id, arrived_at: arrival && received_at + arrival.minutes)
    end
  end

  it "gives the four calculations of the chosen calls, the period it took and null where the page shows a dash",
     :aggregate_failures do
    received("closed", arrival: 10, outcome: "false_alarm")
    received("pending")

    body = api_get(api_v1_statistics_path, user:, params: { from: "2026-09-01", to: "2026-09-30" })

    expect(body["period"]).to eq("from" => "2026-09-01", "to" => "2026-09-30")
    expect(body["total"]).to eq(2)
    expect(body["by_status"]).to include("closed" => 1, "pending" => 1, "cancelled" => 0)
    expect(body["by_outcome"]).to include("false_alarm" => 1, "other" => 0)
    expect(body["response"]).to include("arrivals" => 1, "average" => 10.0)
    expect(body["response"]["by_priority"]).to include("critical" => { "arrivals" => 1, "average" => 10.0 },
                                                       "low" => { "arrivals" => 0, "average" => nil })
    expect(body["response"]["by_car"]).to eq([ { "id" => car.id, "call_sign" => "P-12", "arrivals" => 1, "average" => 10.0 } ])
    expect(body["false_alarms"]).to eq("count" => 1, "closed" => 1, "share" => 100.0)
    expect(body["false_alarm_sites"])
      .to eq([ { "id" => site.id, "name" => "Warehouse No. 3", "contract_number" => site.contract_number, "count" => 1 } ])
  end

  it "takes the current month in Riga time when no period is given (CALC-01)" do
    travel_to(Time.zone.local(2026, 11, 1, 0, 30)) do
      expect(api_get(api_v1_statistics_path, user:)["period"]).to eq("from" => "2026-11-01", "to" => "2026-11-30")
    end
  end

  it "gives null for what cannot be calculated (CALC-02, CALC-03)", :aggregate_failures do
    received("pending")

    body = api_get(api_v1_statistics_path, user:, params: { from: "2026-09-01", to: "2026-09-30" })

    expect([ body["response"]["average"], body["false_alarms"]["share"], body["false_alarm_sites"] ]).to eq([ nil, nil, [] ])
  end

  it "narrows by the filters of the call list (FLT-01)" do
    received("closed", arrival: 10, outcome: "false_alarm")
    received("pending")

    expect(api_get(api_v1_statistics_path, user:, params: { from: "2026-09-01", status: "pending" })["total"]).to eq(1)
  end

  it "answers 422 for a wrong number of sites or a reversed period (CALC-04, FLT-02)", :aggregate_failures do
    expect(api_get(api_v1_statistics_path, user:, params: { top: "0" }))
      .to eq("errors" => { "base" => [ "Number of sites must be from 1 to 50" ] })
    expect(response).to have_http_status(:unprocessable_content)
    expect(api_get(api_v1_statistics_path, user:, params: { from: "2026-10-02", to: "2026-10-01" }))
      .to eq("errors" => { "base" => [ "Period start is after period end" ] })
  end
end
