require "rails_helper"

RSpec.describe CrewNoticeJob do
  include_context "without the seeded records"

  it "tells the crew of the call's car (CRW-04)" do
    call = create(:alarm_call)
    notice = instance_double(CrewNotice, deliver: nil)
    allow(CrewNotice).to receive(:new).with(call).and_return(notice)

    described_class.perform_now(call)

    expect(notice).to have_received(:deliver)
  end

  it "tells the crew of a further car when it is given that car (BR-22)" do
    call = create(:alarm_call)
    car = create(:patrol_car)
    notice = instance_double(CrewNotice, deliver: nil)
    allow(CrewNotice).to receive(:new).with(call, car:).and_return(notice)

    described_class.perform_now(call, car)

    expect(notice).to have_received(:deliver)
  end

  it "drops the notice of a call deleted before it went" do
    call = create(:alarm_call)
    queued = described_class.new(call).serialize
    Call.where(id: call.id).delete_all

    expect { ActiveJob::Base.execute(queued) }.not_to raise_error
  end
end
