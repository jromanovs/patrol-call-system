require "rails_helper"

RSpec.describe CarPosition do
  include_context "without the seeded records"

  it { is_expected.to belong_to(:patrol_car) }

  it "takes a place on the earth with the time it was taken (TRK-03)", :aggregate_failures do
    expect(build(:car_position)).to be_valid
    expect(build(:car_position, latitude: 91)).not_to be_valid
    expect(build(:car_position, longitude: nil)).not_to be_valid
    expect(build(:car_position, accuracy: -1)).not_to be_valid
    expect(build(:car_position, recorded_at: nil)).not_to be_valid
  end

  it "reads what Traccar Client sends, the phone's time in seconds or the time of arrival", :aggregate_failures do
    sent = described_class.reported({ lat: "56.9391", lon: "24.1559", accuracy: "9.4", timestamp: "1791021840" })
    expect(sent).to eq(latitude: 56.9391, longitude: 24.1559, accuracy: 9, recorded_at: Time.zone.at(1_791_021_840))

    travel_to(Time.zone.local(2026, 10, 3, 13, 4)) do
      expect(described_class.reported({ lat: "56.9", lon: "24.1" }))
        .to eq(latitude: 56.9, longitude: 24.1, accuracy: nil, recorded_at: Time.current)
    end
  end

  it "gives the newest position of each car" do
    old, new = create_list(:patrol_car, 2)
    create(:car_position, patrol_car: old, recorded_at: 2.minutes.ago)
    newest = create(:car_position, patrol_car: old, recorded_at: 1.minute.ago)
    other = create(:car_position, patrol_car: new, recorded_at: 5.minutes.ago)

    expect(described_class.latest).to contain_exactly(newest, other)
  end

  it "deletes the positions older than 30 days (BR-20)" do
    kept = create(:car_position, recorded_at: 29.days.ago)
    create(:car_position, recorded_at: 31.days.ago)
    described_class.prune

    expect(described_class.all).to contain_exactly(kept)
  end

  it "goes with its car" do
    car = create(:car_position).patrol_car

    expect { car.destroy }.to change(described_class, :count).by(-1)
  end
end
