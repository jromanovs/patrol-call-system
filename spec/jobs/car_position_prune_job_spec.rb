require "rails_helper"
require "fugit"

RSpec.describe CarPositionPruneJob do
  include_context "without the seeded records"

  it "deletes the positions older than the period, of tracked cars and of others alike (TRK-05, BR-20)",
     :aggregate_failures do
    untracked = create(:patrol_car, position_source: :not_tracked)
    kept = [ create(:car_position, recorded_at: 23.months.ago),
             create(:car_position, patrol_car: untracked, recorded_at: 31.days.ago) ]
    create(:car_position, recorded_at: 25.months.ago)
    create(:car_position, patrol_car: untracked, recorded_at: 25.months.ago)

    described_class.perform_now

    expect(CarPosition.all).to match_array(kept)
  end

  it "follows the period the administrator set" do
    Setting.current.update!(position_months: 6)
    kept = create(:car_position, recorded_at: 5.months.ago)
    create(:car_position, recorded_at: 7.months.ago)

    described_class.perform_now

    expect(CarPosition.all).to contain_exactly(kept)
  end

  it "is planned every night at 03:30 Riga time", :aggregate_failures do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "prune_car_positions")
    after = EtOrbi.make_time(Time.zone.local(2026, 10, 2, 12, 0))

    expect(task["class"]).to eq("CarPositionPruneJob")
    expect(Fugit.parse(task["schedule"]).next_time(after).to_t).to eq(Time.zone.local(2026, 10, 3, 3, 30))
  end
end
