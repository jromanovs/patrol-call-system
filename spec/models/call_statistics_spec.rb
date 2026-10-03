require "rails_helper"

RSpec.describe CallStatistics do
  include_context "without the seeded records"

  # Beta alone in the east, the rest in the north.
  let(:sites) do
    %w[ Alpha Beta Gamma Delta Epsilon Zeta ].to_h do |name|
      [ name, create(:guarded_site, name: "#{name} Site", district: name == "Beta" ? :east : :north) ]
    end
  end
  let(:cars) { %w[ P-1 P-2 P-3 ].to_h { |sign| [ sign, create(:patrol_car, call_sign: sign) ] } }
  let(:statistics) { described_class.new(Call.all) }

  # A call received on 10.09.2026 09:00 and put in its status directly.
  def record(site, priority, status, car: nil, arrival: nil, outcome: nil, acceptance: nil)
    received_at = Time.zone.local(2026, 9, 10, 9, 0)
    create(:alarm_call, guarded_site: sites.fetch(site), priority:, received_at:).tap do |call|
      call.update_columns(status: Call.statuses.fetch(status.to_s), patrol_car_id: cars[car]&.id,
                          outcome: outcome && Call.outcomes.fetch(outcome.to_s),
                          arrived_at: arrival && received_at + arrival.minutes,
                          dispatched_at: acceptance && received_at + 1.minute,
                          accepted_at: acceptance && received_at + 1.minute + acceptance.minutes)
    end
  end

  def sites_of(statistics) = statistics.false_alarm_sites.map { |site, count| [ site.name, count ] }

  context "with two closed calls, one cancelled, one on scene and one pending" do
    before do
      record("Beta", :critical, :closed, car: "P-1", arrival: 10, outcome: :false_alarm)
      record("Alpha", :normal, :closed, car: "P-1", arrival: 20, outcome: :intrusion_confirmed)
      record("Gamma", :normal, :on_scene, car: "P-2", arrival: 25)
      record("Beta", :low, :cancelled)
      record("Alpha", :high, :pending)
    end

    it "counts the calls in each status, in the alphabet of the names, and in total (CALC-01)", :aggregate_failures do
      expect(statistics.by_status).to eq([ [ "accepted", 0 ], [ "cancelled", 1 ], [ "closed", 2 ], [ "dispatched", 0 ], [ "on_scene", 1 ],
                                           [ "pending", 1 ] ])
      expect(statistics.total).to eq(5)
    end

    it "counts the calls with each outcome (CALC-01)" do
      expect(statistics.by_outcome).to eq([ [ "false_alarm", 1 ], [ "fire_confirmed", 0 ], [ "help_given", 0 ],
                                            [ "intrusion_confirmed", 1 ], [ "other", 0 ], [ "technical_fault", 0 ] ])
    end

    it "averages the response time overall and per priority, critical first (CALC-02)", :aggregate_failures do
      expect([ statistics.arrivals, statistics.response ]).to eq([ 3, 18.3 ])
      expect(statistics.response_by_priority)
        .to eq([ [ "critical", 1, 10.0 ], [ "high", 0, nil ], [ "normal", 2, 22.5 ], [ "low", 0, nil ] ])
    end

    it "counts the accepted calls and averages the time from sending to acceptance (CALC-02)", :aggregate_failures do
      record("Delta", :normal, :accepted, car: "P-1", acceptance: 2)
      record("Epsilon", :normal, :on_scene, car: "P-3", acceptance: 3, arrival: 15)

      expect([ statistics.acceptances, statistics.acceptance ]).to eq([ 2, 2.5 ])
    end

    it "averages the response time per car with the number of arrivals (CALC-02)" do
      expect(statistics.response_by_car.map { |car, *values| [ car.call_sign, *values ] })
        .to eq([ [ "P-1", 2, 15.0 ], [ "P-2", 1, 25.0 ], [ "P-3", 0, nil ] ])
    end

    it "gives the share of false alarms among the closed calls with both counts (CALC-03)" do
      expect(statistics.false_alarms).to have_attributes(count: 1, closed: 2, share: 50.0)
    end

    it "counts only the calls it is given, such as those of a filter (FLT-01)", :aggregate_failures do
      closed = described_class.new(CallFilter.new(status: "closed").selected)

      expect(closed.total).to eq(2)
      expect(closed.response).to eq(15.0)
    end

    it "counts all four calculations over a filter that searches the sites (FLT-01)", :aggregate_failures do
      beta = described_class.new(CallFilter.new(district: "east", q: "beta").selected)

      expect(beta.by_status.to_h.select { |_status, count| count.positive? }).to eq("cancelled" => 1, "closed" => 1)
      expect([ beta.arrivals, beta.response ]).to eq([ 1, 10.0 ])
      expect(beta.false_alarms).to have_attributes(count: 1, closed: 1, share: 100.0)
      expect(sites_of(beta)).to eq([ [ "Beta Site", 1 ] ])
    end
  end

  it "gives no average and no share instead of an error when nothing arrived or closed (CALC-02, CALC-03)",
     :aggregate_failures do
    record("Alpha", :high, :pending)

    expect(statistics.response).to be_nil
    expect(statistics.response_by_priority.map(&:last)).to all(be_nil)
    expect(statistics.false_alarms).to have_attributes(count: 0, closed: 0, share: nil)
    expect(statistics.false_alarm_sites).to be_empty
  end

  describe "sites with the most false alarms (CALC-04)" do
    before do
      %w[ Beta Beta Alpha Alpha Zeta Gamma Epsilon Delta ].each { |site| record(site, :high, :closed, outcome: :false_alarm) }
      record("Gamma", :high, :closed, outcome: :intrusion_confirmed)
    end

    it "lists the N sites with the most, equal counts by name" do
      expect(sites_of(described_class.new(Call.all, top: "2"))).to eq([ [ "Alpha Site", 2 ], [ "Beta Site", 2 ] ])
    end

    it "lists 5 by default" do
      expect(sites_of(statistics)).to eq([ [ "Alpha Site", 2 ], [ "Beta Site", 2 ], [ "Delta Site", 1 ], [ "Epsilon Site", 1 ],
                                          [ "Gamma Site", 1 ] ])
    end

    it "takes N from 1 to 50 and refuses any other value, using 5 instead", :aggregate_failures do
      %w[ 1 50 ].each { |top| expect(described_class.new(Call.all, top:)).to be_valid }
      %w[ 0 51 x ].each do |top|
        refused = described_class.new(Call.all, top:)
        expect(refused).not_to be_valid
        expect(refused.errors.full_messages).to eq([ "Number of sites must be from 1 to 50" ])
        expect(sites_of(refused).size).to eq(5)
      end
    end
  end
end
