require "rails_helper"

RSpec.describe Call do
  include_context "without the seeded records"

  def finished(received_at, status = :closed)
    create(:alarm_call, received_at:).tap { |call| call.update_column(:status, described_class.statuses[status]) }
  end

  describe "kept for the period the administrator set (BR-23)" do
    before { travel_to(Time.zone.local(2026, 10, 4, 12, 0)) }

    it "refuses the deletion of a finished call received within the period, naming the last day it is kept",
       :aggregate_failures do
      call = finished(Time.zone.local(2026, 3, 14, 9, 12))

      expect(call.destroy).to be(false)
      expect(call.errors[:base]).to eq([ "Call is kept until 14.03.2028 and cannot be deleted" ])
      expect(described_class.exists?(call.id)).to be(true)
    end

    it "keeps a call received on the first kept day and lets one of the day before go", :aggregate_failures do
      kept = finished(Time.zone.local(2024, 10, 4, 0, 10))
      old = finished(Time.zone.local(2024, 10, 3, 23, 50), :cancelled)

      expect([ kept.kept?, kept.kept_until ]).to eq([ true, Date.new(2026, 10, 4) ])
      expect(old.kept?).to be(false)
      expect(old.destroy).to be_truthy
    end

    it "follows the period the administrator set" do
      Setting.current.update!(call_months: 3)

      expect([ finished(Time.zone.local(2026, 7, 3, 12, 0)), finished(Time.zone.local(2026, 7, 4, 12, 0)) ].map(&:kept?))
        .to eq([ false, true ])
    end

    it "says of an active call that it is active, whatever its age" do
      active = create(:alarm_call, received_at: Time.zone.local(2020, 1, 1))

      expect([ active.destroy, active.errors[:base] ])
        .to eq([ false, [ "Active call cannot be deleted; cancel or close it first" ] ])
    end
  end

  it "counts by calendar months: a call of a month's last day is kept to the end of the shorter month",
     :aggregate_failures do
    Setting.current.update!(call_months: 3)
    call = finished(Time.zone.local(2025, 11, 30, 12, 0))

    travel_to(Time.zone.local(2026, 2, 28, 12, 0))
    expect([ call.kept_until, call.kept? ]).to eq([ Date.new(2026, 2, 28), true ])
    travel_to(Time.zone.local(2026, 3, 1, 12, 0))
    expect(call.kept?).to be(false)
  end

  # Every day of May past the 28th falls back on 28 February three months
  # earlier, so the last kept day is found, not computed as the same date.
  it "keeps a call of February's last day to the end of the month its period ends in", :aggregate_failures do
    Setting.current.update!(call_months: 3)
    call = finished(Time.zone.local(2023, 2, 28, 12, 0))

    travel_to(Time.zone.local(2023, 5, 31, 12, 0))
    expect([ call.kept_until, call.kept? ]).to eq([ Date.new(2023, 5, 31), true ])
    travel_to(Time.zone.local(2023, 6, 1, 12, 0))
    expect(call.kept?).to be(false)
  end
end
