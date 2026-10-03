require "rails_helper"

RSpec.describe CrewReminderJob do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car) }
  let(:call) { create(:alarm_call).tap { |sent| CallStep.new(sent, create(:user)).dispatch(car) } }
  let(:notice) { instance_double(CrewNotice, deliver: nil) }

  before { allow(CrewNotice).to receive(:new).and_return(notice) }

  it "reminds the crew and plans the next reminder a minute later (CRW-06)", :aggregate_failures do
    call
    freeze_time do
      expect { described_class.perform_now(call, 2) }
        .to have_enqueued_job(described_class).with(call, 3).at(1.minute.from_now)
    end
    expect(CrewNotice).to have_received(:new).with(call, reminder: 2)
    expect(notice).to have_received(:deliver)
  end

  it "stops after the fifth and has every open screen show the call unanswered", :aggregate_failures do
    call

    expect { described_class.perform_now(call, 5) }
      .to have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with("board", content: a_string_including('action="refresh"'))
    expect(described_class).not_to have_been_enqueued.with(call, 6)
    expect(notice).to have_received(:deliver)
  end

  it "reminds no more once the call is accepted, the car has arrived or the call is cancelled", :aggregate_failures do
    accepted = call.tap { CallStep.new(call, create(:user)).accept }
    arrived = create(:alarm_call).tap { |other| CallStep.new(other, create(:user)).dispatch(create(:patrol_car)) }
    CallStep.new(arrived, create(:user)).arrive
    cancelled = create(:alarm_call).tap { |other| CallStep.new(other, create(:user)).dispatch(create(:patrol_car)) }
    CallStep.new(cancelled, create(:user)).cancel("")

    [ accepted, arrived, cancelled ].each do |finished|
      expect { described_class.perform_now(finished.reload, 1) }.not_to have_enqueued_job(described_class)
    end
    expect(CrewNotice).not_to have_received(:new)
  end

  it "drops the reminder of a call deleted before it went" do
    queued = described_class.new(call, 1).serialize
    Call.where(id: call.id).delete_all

    expect { ActiveJob::Base.execute(queued) }.not_to raise_error
  end
end
