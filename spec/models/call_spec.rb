require "rails_helper"

RSpec.describe Call do
  it { is_expected.to define_enum_for(:priority).with_values(low: 0, normal: 1, high: 2, critical: 3) }

  it { is_expected.to define_enum_for(:status).with_values(pending: 0, dispatched: 1, on_scene: 2, closed: 3, cancelled: 4) }

  it "never saves an object of the base class" do
    call = described_class.new(guarded_site: create(:guarded_site), registered_by: create(:user), priority: :normal)

    expect(call.save).to be(false)
  end

  it "stays as it is once closed or cancelled (BR-7)", :aggregate_failures do
    call = create(:client_call)
    call.update_column(:status, described_class.statuses[:cancelled])

    expect(call.update(priority: :low)).to be(false)
    expect(call.errors[:base]).to include("A closed or cancelled call cannot be changed")
  end

  describe ".on_board" do
    it "lists active calls, critical first, then the longest wait (DSP-03)" do
      travel_to Time.zone.local(2026, 10, 1, 15, 45) do
        low = create(:alarm_call, alarm_type: :power_failure, received_at: 33.minutes.ago)
        old_critical = create(:alarm_call, alarm_type: :fire, received_at: 13.minutes.ago)
        new_critical = create(:alarm_call, alarm_type: :panic, received_at: 4.minutes.ago)
        high = create(:alarm_call, alarm_type: :intrusion, received_at: 25.minutes.ago)
        create(:alarm_call, received_at: 50.minutes.ago).update_column(:status, described_class.statuses[:closed])

        expect(described_class.on_board).to eq([ old_critical, new_critical, high, low ])
      end
    end
  end

  describe "#waiting_minutes" do
    it "counts whole minutes since the call was received" do
      travel_to Time.zone.local(2026, 10, 1, 15, 45, 30) do
        expect(build(:alarm_call, received_at: Time.zone.local(2026, 10, 1, 15, 32)).waiting_minutes).to eq(13)
      end
    end
  end
end
