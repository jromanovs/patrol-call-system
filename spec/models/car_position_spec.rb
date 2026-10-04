require "rails_helper"

RSpec.describe CarPosition do
  include_context "without the seeded records"

  it { is_expected.to belong_to(:patrol_car) }
  it { is_expected.to define_enum_for(:source).with_values(traccar: 1, crew_phone: 2) }

  it "takes a place on the earth with the time it was taken (TRK-03)", :aggregate_failures do
    expect(build(:car_position)).to be_valid
    expect(build(:car_position, latitude: 91)).not_to be_valid
    expect(build(:car_position, longitude: nil)).not_to be_valid
    expect(build(:car_position, accuracy: -1)).not_to be_valid
    expect(build(:car_position, recorded_at: nil)).not_to be_valid
  end

  it "reads what Traccar Client sends, the phone's time in seconds or the time of arrival", :aggregate_failures do
    travel_to(Time.zone.local(2026, 10, 3, 13, 4)) do
      taken = 2.minutes.ago
      sent = described_class.reported({ lat: "56.95", lon: "24.1", accuracy: "9.4", timestamp: taken.to_i.to_s })
      expect(sent).to eq(latitude: 56.95, longitude: 24.1, accuracy: 9, recorded_at: taken)

      expect(described_class.reported({ lat: "56.9", lon: "24.1" }))
        .to eq(latitude: 56.9, longitude: 24.1, accuracy: nil, recorded_at: Time.current)
      expect(described_class.reported({ lat: "56.9", lon: "24.1", timestamp: 6.minutes.from_now.to_i.to_s })[:recorded_at])
        .to eq(Time.current)
    end
  end

  it "counts a position kept without a source as Traccar Client's, as the previous version keeps them" do
    expect(described_class.new.source).to eq("traccar")
  end

  it "reads what the crew's phone sends, taken at the time it came (TRK-04)" do
    travel_to(Time.zone.local(2026, 10, 3, 12, 4)) do
      expect(described_class.from_phone({ latitude: 56.95, longitude: "24.1", accuracy: 9.4 }))
        .to eq(latitude: 56.95, longitude: 24.1, accuracy: 9, recorded_at: Time.current)
    end
  end

  it "gives the newest position taken by each car within 30 days, whatever came last", :aggregate_failures do
    old, new = create_list(:patrol_car, 2)
    newest = create(:car_position, patrol_car: old, recorded_at: 1.minute.ago)
    create(:car_position, patrol_car: old, recorded_at: 2.minutes.ago)
    other = create(:car_position, patrol_car: new, recorded_at: 5.minutes.ago)
    create(:car_position, patrol_car: create(:patrol_car), recorded_at: 31.days.ago)

    expect(described_class.latest).to contain_exactly(newest, other)
  end

  it "deletes the positions that came before the period the administrator set, 24 months unless changed (BR-20)" do
    kept = create(:car_position, created_at: 23.months.ago)
    create(:car_position, created_at: 25.months.ago)
    described_class.prune

    expect(described_class.all).to contain_exactly(kept)
  end

  it "keeps a position to the day: a day short of the period it stays, a day past it goes" do
    freeze_time
    kept = create(:car_position, created_at: 24.months.ago + 1.day)
    create(:car_position, created_at: 24.months.ago - 1.day)
    described_class.prune

    expect(described_class.all).to contain_exactly(kept)
  end

  it "counts the period from the day a position came, whatever the phone's clock said" do
    kept = create(:car_position, recorded_at: Time.zone.local(2020, 1, 1), created_at: 1.day.ago)
    described_class.prune

    expect(described_class.all).to contain_exactly(kept)
  end

  it "gives the newest position of each car of any age when no age is asked for" do
    old = create(:car_position, recorded_at: 40.days.ago)

    expect(described_class.latest(since: nil)).to contain_exactly(old)
  end

  it "is found by the day it came through an index: the nightly deletion and the tracking page read by it",
     :aggregate_failures do
    columns = described_class.connection.indexes(:car_positions).map(&:columns)

    expect(columns).to include([ "created_at" ], %w[ patrol_car_id recorded_at ])
    expect(columns).not_to include([ "recorded_at" ])
  end

  it "keeps its car from being deleted while it is kept itself (BR-9, BR-20)", :aggregate_failures do
    car = create(:car_position, created_at: Time.zone.local(2026, 10, 3, 0, 30)).patrol_car

    expect { car.destroy }.not_to change(described_class, :count)
    expect(car).to be_persisted
    expect(car.kept_reason)
      .to eq("Car has positions kept since 03.10.2026 and cannot be deleted; put it out of service instead")
  end
end
