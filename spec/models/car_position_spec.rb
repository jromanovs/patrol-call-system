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

  it "deletes the positions older than the period the administrator set, 24 months unless changed (BR-20)" do
    kept = create(:car_position, recorded_at: 23.months.ago)
    create(:car_position, recorded_at: 25.months.ago)
    described_class.prune

    expect(described_class.all).to contain_exactly(kept)
  end

  it "goes with its car" do
    car = create(:car_position).patrol_car

    expect { car.destroy }.to change(described_class, :count).by(-1)
  end
end
