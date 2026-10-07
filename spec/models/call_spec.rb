require "rails_helper"

RSpec.describe Call do
  it { is_expected.to define_enum_for(:priority).with_values(low: 0, normal: 1, high: 2, critical: 3) }

  it { is_expected.to define_enum_for(:status).with_values(pending: 0, dispatched: 1, accepted: 5, on_scene: 2, closed: 3, cancelled: 4) }

  it "never saves an object of the base class" do
    call = described_class.new(guarded_site: create(:guarded_site), registered_by: create(:user), priority: :normal)

    expect(call.save).to be(false)
  end

  describe "status transitions (2.10)" do
    it "knows which status may follow which", :aggregate_failures do
      expect(described_class.next_statuses("pending")).to eq(%w[dispatched cancelled])
      expect(described_class.next_statuses("dispatched")).to eq(%w[accepted on_scene cancelled])
      expect(described_class.next_statuses("accepted")).to eq(%w[on_scene cancelled])
      expect(described_class.next_statuses("on_scene")).to eq(%w[closed])
      expect(described_class.next_statuses("closed")).to eq([])
    end

    it "refuses a status that may not follow the current one", :aggregate_failures do
      call = create(:client_call)

      expect(call.update(status: :closed)).to be(false)
      expect(call.errors[:status]).to include("cannot change from pending to closed")
    end
  end

  describe "#fresh? (DYN-10)" do
    it "holds for the first seconds after a call is received, and no longer", :aggregate_failures do
      call = create(:alarm_call)

      expect(call).to be_fresh
      travel(described_class::FRESH - 1.second) { expect(call).to be_fresh }
      travel(described_class::FRESH + 1.second) { expect(call).not_to be_fresh }
    end

    it "lasts longer than the three pulses of the card and well under a minute" do
      expect(described_class::FRESH).to be_between(3.seconds, 30.seconds)
    end
  end

  describe "#arrival (DSP-03, DSP-05, CRW-06)" do
    let(:call) { create(:alarm_call) }
    let(:now) { Time.zone.local(2026, 10, 3, 6, 0) }

    def state(status, sent_minutes_ago = nil)
      call.update_columns(status: described_class.statuses.fetch(status), dispatched_at: sent_minutes_ago&.minutes&.before(now))
      call.arrival(now)
    end

    it "names the state of the car: waiting, sent, unanswered after 5 minutes, on the way once accepted, on site",
       :aggregate_failures do
      expect(state("pending")).to eq("waiting")
      expect(state("dispatched", 4)).to eq("sent")
      expect(state("dispatched", 5)).to eq("unanswered")
      expect(state("accepted", 9)).to eq("on-the-way")
      expect(state("on_scene", 9)).to eq("on-site")
    end

    it "tells an arrival marked far from the site, or without a position, from one on site (CRW-09)",
       :aggregate_failures do
      arrival = create(:step_position, call:, distance: 200)
      create(:step_position, call:, step: :closing, distance: 5000)
      expect(state("on_scene", 9)).to eq("on-site")

      arrival.update!(distance: 201)
      expect(call.reload.arrival(now)).to eq("far")

      arrival.update!(latitude: nil, longitude: nil, accuracy: nil, distance: nil)
      expect(call.reload.arrival(now)).to eq("no-position")
    end
  end

  it "counts the response time in minutes with one decimal (2.10)" do
    call = build(:client_call, received_at: Time.zone.local(2026, 10, 2, 9, 0), arrived_at: Time.zone.local(2026, 10, 2, 9, 12, 30))

    expect(call.response_minutes).to eq(12.5)
  end

  it do
    expect(described_class.new).to define_enum_for(:outcome)
      .with_values(false_alarm: 0, intrusion_confirmed: 1, fire_confirmed: 2, technical_fault: 3, other: 4, help_given: 5)
  end

  it "stays as it is once closed or cancelled (BR-7)", :aggregate_failures do
    call = create(:client_call)
    call.update_column(:status, described_class.statuses[:cancelled])

    expect(call.update(priority: :low)).to be(false)
    expect(call.errors[:base]).to include("A closed or cancelled call cannot be changed")
  end

  it "is deleted only when closed or cancelled (BR-8)", :aggregate_failures do
    calls = described_class.statuses.to_h do |status, value|
      [ status, create(:client_call, received_at: 25.months.ago).tap { |call| call.update_column(:status, value) } ]
    end

    calls.values_at(*described_class::ACTIVE).each do |active|
      expect(active.destroy).to be(false), active.status
      expect(active.errors[:base]).to eq([ "Active call cannot be deleted; cancel or close it first" ])
    end
    expect(calls.values_at("closed", "cancelled").map(&:destroy)).to all(be_destroyed)
    expect(described_class.where(id: calls.values.map(&:id)).pluck(:status)).to match_array(described_class::ACTIVE)
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

  describe "#handling_minutes (2.10)" do
    let(:received_at) { Time.zone.local(2026, 10, 1, 9, 0) }

    it "counts whole minutes from receipt to closing or cancellation" do
      expect(build(:alarm_call, received_at:, closed_at: received_at + 42.minutes + 50.seconds).handling_minutes).to eq(42)
    end

    it "counts an active call until now" do
      travel_to(received_at + 25.minutes + 10.seconds) do
        expect(build(:alarm_call, received_at:).handling_minutes).to eq(25)
      end
    end
  end
end
