require "rails_helper"

RSpec.describe CallFilter do
  include_context "without the seeded records"

  # Four calls that differ in every criterion and every sorted column.
  let!(:records) do
    north = create(:guarded_site, name: "Alpha Office", contract_number: "C-00201", district: :north)
    centre = create(:guarded_site, name: "Beta Shop", contract_number: "C-00202", district: :centre)
    cars = [ create(:patrol_car, call_sign: "P-1"), create(:patrol_car, call_sign: "P-2") ]
    {
      centre:, first_car: cars.first,
      fire: create(:alarm_call, guarded_site: north, alarm_type: :fire, received_at: riga(2026, 10, 1, 0, 0)),
      client: create(:client_call, guarded_site: centre, caller_name: "Example Person", received_at: riga(2026, 10, 1, 23, 59))
        .tap { |call| call.update_columns(status: Call.statuses[:dispatched], patrol_car_id: cars.first.id) },
      power: create(:alarm_call, guarded_site: centre, alarm_type: :power_failure, received_at: riga(2026, 9, 30, 23, 59))
        .tap { |call| call.update_columns(status: Call.statuses[:closed], patrol_car_id: cars.last.id, outcome: 0) },
      late: create(:client_call, guarded_site: north, priority: :high, caller_name: "Other Caller",
                                 received_at: riga(2026, 10, 2, 0, 0))
        .tap { |call| call.update_columns(status: Call.statuses[:cancelled]) }
    }
  end

  %i[ centre first_car fire client power late ].each { |name| define_method(name) { records.fetch(name) } }

  def riga(*time) = Time.zone.local(*time)

  def found(**criteria) = described_class.new(criteria).results.to_a

  it "lists every call, newest first, without criteria" do
    expect(found).to eq([ late, client, fire, power ])
  end

  it "narrows by each of the seven criteria (FLT-01)", :aggregate_failures do
    expect(found(status: "pending")).to eq([ fire ])
    expect(found(priority: "critical")).to eq([ fire ])
    expect(found(kind: "client")).to eq([ late, client ])
    expect(found(district: "north")).to eq([ late, fire ])
    expect(found(site_id: centre.id.to_s, car_id: first_car.id.to_s)).to eq([ client ])
  end

  it "combines the criteria (FLT-01)" do
    expect(found(kind: "alarm", district: "centre")).to eq([ power ])
  end

  it "takes one day from 00:00 to 23:59 Riga time (FLT-02)" do
    expect(found(from: "2026-10-01", to: "2026-10-01")).to eq([ client, fire ])
  end

  it "refuses a period whose start is after its end and does not filter by it (FLT-02)", :aggregate_failures do
    filter = described_class.new(from: "2026-10-02", to: "2026-10-01")

    expect(filter).not_to be_valid
    expect(filter.errors.full_messages).to eq([ "Period start is after period end" ])
    expect(filter.results.to_a).to eq([ late, client, fire, power ])
  end

  it "searches site name, contract number and caller from 2 characters", :aggregate_failures do
    expect(found(q: "EXAMPLE")).to eq([ client ])
    expect(found(q: "alpha")).to eq([ late, fire ])
    expect(found(q: "c-00202")).to eq([ client, power ])
    expect(found(q: "a").size).to eq(4)
  end

  it "sorts by every column both ways; equal values by received time, newest first (SRT-01)", :aggregate_failures do
    orders = {
      "received_at" => [ [ power, fire, client, late ], [ late, client, fire, power ] ],
      "priority" => [ [ fire, late, client, power ], [ power, client, late, fire ] ],
      "site" => [ [ late, fire, client, power ], [ client, power, late, fire ] ],
      "type" => [ [ fire, power, late, client ], [ late, client, fire, power ] ],
      "status" => [ [ late, power, client, fire ], [ fire, client, power, late ] ],
      "car" => [ [ client, power, late, fire ], [ power, client, late, fire ] ],
      "outcome" => [ [ power, late, client, fire ], [ power, late, client, fire ] ]
    }

    orders.each do |column, (ascending, descending)|
      expect(found(sort: column, direction: "asc")).to eq(ascending), "#{column} ascending"
      expect(found(sort: column, direction: "desc")).to eq(descending), "#{column} descending"
    end
  end
end
