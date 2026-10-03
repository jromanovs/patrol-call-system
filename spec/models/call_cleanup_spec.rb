require "rails_helper"

RSpec.describe CallCleanup do
  include_context "without the seeded records"

  # The four calls of the readiness criteria in issue #13.
  let!(:records) do
    {
      closed: received(2026, 8, 31, 23, 59, status: :closed, outcome: :false_alarm),
      cancelled: received(2026, 8, 31, 12, 0, status: :cancelled, kind: :client_call),
      pending: received(2026, 8, 31, 12, 0, status: :pending),
      later: received(2026, 9, 1, 0, 0, status: :closed, outcome: :technical_fault)
    }
  end

  def received(*time, status:, kind: :alarm_call, outcome: nil)
    create(kind, received_at: Time.zone.local(*time)).tap do |call|
      call.update_columns(status: Call.statuses.fetch(status.to_s), outcome: outcome && Call.outcomes.fetch(outcome.to_s))
    end
  end

  def cleanup(**criteria) = described_class.new(before: "2026-09-01", statuses: %w[ closed cancelled ], **criteria)

  def messages(cleanup) = cleanup.tap(&:validate).errors.full_messages

  it "matches the finished calls received before 00:00 Riga time of the day (DEL-07)" do
    expect(cleanup.calls).to contain_exactly(records[:closed], records[:cancelled])
  end

  it "narrows by status, call type and outcome (DEL-07)", :aggregate_failures do
    expect(cleanup(statuses: %w[ cancelled ]).calls).to eq([ records[:cancelled] ])
    expect(cleanup(kind: "alarm").calls).to eq([ records[:closed] ])
    expect(cleanup(outcome: "false_alarm", before: "2026-09-02").calls).to eq([ records[:closed] ])
  end

  it "never matches an active call, even when asked for (BR-8)" do
    expect(cleanup(statuses: %w[ pending closed ]).calls).to eq([ records[:closed] ])
  end

  it "takes today in Riga time and refuses a later day (DEL-08)", :aggregate_failures do
    # 3 October in Riga is still 2 October in UTC, the zone of the CI machine.
    travel_to(Time.utc(2026, 10, 2, 21, 30)) do
      expect(cleanup(before: "2026-10-03")).to be_valid
      expect(messages(cleanup(before: "2026-10-04"))).to eq([ "Received before cannot be in the future" ])
    end
  end

  it "needs a day and at least one of closed and cancelled (DEL-07, DEL-08)", :aggregate_failures do
    expect(messages(cleanup(before: ""))).to eq([ "Choose the day for Received before" ])
    expect(messages(cleanup(statuses: []))).to eq([ "Choose closed, cancelled or both" ])
    expect(messages(cleanup(statuses: %w[ pending ]))).to eq([ "Choose closed, cancelled or both" ])
  end

  describe "#delete (DEL-07)" do
    # What the preview hands to the confirmation: the fingerprint of the
    # calls that matched at that moment.
    let!(:previewed) { described_class.fingerprint(cleanup.ids) }

    it "deletes exactly the previewed calls and leaves the rest", :aggregate_failures do
      expect(cleanup.delete(previewed)).to eq(2)
      expect(Call.all).to contain_exactly(records[:pending], records[:later])
    end

    it "deletes the crew's positions with their calls (BR-18)" do
      create(:step_position, call: records[:closed])
      kept = create(:step_position, call: records[:later])
      cleanup.delete(previewed)

      expect(StepPosition.all).to contain_exactly(kept)
    end

    it "deletes the crew's photos with their calls, their files too (BR-19)", :aggregate_failures do
      create(:call_photo, call: records[:closed])
      kept = create(:call_photo, call: records[:later])

      expect { cleanup.delete(previewed) }.to change(ActiveStorage::Attachment, :count).by(-1)
      expect(CallPhoto.all).to contain_exactly(kept)
    end

    it "deletes nothing when more calls match than in the preview", :aggregate_failures do
      records[:pending].update_column(:status, Call.statuses[:cancelled])

      expect { cleanup.delete(previewed) }.to raise_error(CallCleanup::Changed, "3 calls match now")
      expect(Call.count).to eq(4)
    end

    it "deletes nothing when other calls match, even as many as in the preview", :aggregate_failures do
      records[:closed].delete
      records[:pending].update_column(:status, Call.statuses[:cancelled])

      expect { cleanup.delete(previewed) }.to raise_error(CallCleanup::Changed, "2 calls match now")
      expect(Call.count).to eq(3)
    end
  end
end
