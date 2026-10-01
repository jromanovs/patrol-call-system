require "rails_helper"

RSpec.describe AlarmCall do
  subject { build(:alarm_call) }

  describe "validations" do
    it { is_expected.to define_enum_for(:alarm_type).with_values(intrusion: 0, fire: 1, panic: 2, tamper: 3, power_failure: 4) }
    it { is_expected.to validate_numericality_of(:sensor_zone).only_integer.is_in(1..99).with_message("must be from 1 to 99") }
    it { is_expected.to belong_to(:guarded_site) }
    it { is_expected.to belong_to(:registered_by).class_name("User") }
    it { is_expected.to validate_length_of(:description).is_at_most(1000) }
  end

  it "is a call of the alarm kind" do
    expect(described_class.superclass).to eq(Call)
  end

  it "starts pending, received now", :aggregate_failures do
    freeze_time do
      call = create(:alarm_call)

      expect(call.status).to eq("pending")
      expect(call.received_at).to eq(Time.current)
    end
  end

  it "takes the priority from the alarm type (BR-2)", :aggregate_failures do
    { panic: "critical", fire: "critical", intrusion: "high", tamper: "normal", power_failure: "low" }.each do |type, priority|
      expect(create(:alarm_call, alarm_type: type).priority).to eq(priority)
    end
  end

  it "keeps a priority the dispatcher chose" do
    expect(create(:alarm_call, alarm_type: :panic, priority: :low).priority).to eq("low")
  end

  it "accepts zones 1 and 99 and refuses 0 and 100 (ADD-06)", :aggregate_failures do
    expect(build(:alarm_call, sensor_zone: 1)).to be_valid
    expect(build(:alarm_call, sensor_zone: 99)).to be_valid
    expect(build(:alarm_call, sensor_zone: 0)).not_to be_valid
    expect(build(:alarm_call, sensor_zone: 100)).not_to be_valid
  end

  it "refuses a time of receipt in the future (ADD-06)", :aggregate_failures do
    freeze_time do
      call = build(:alarm_call, received_at: 1.minute.from_now)

      expect(call).not_to be_valid
      expect(call.errors[:received_at]).to include("cannot be in the future")
    end
  end

  it "refuses a site whose contract is suspended (BR-1)", :aggregate_failures do
    call = build(:alarm_call, guarded_site: create(:guarded_site, :suspended))

    expect(call).not_to be_valid
    expect(call.errors[:guarded_site]).to include("has a suspended contract")
  end

  it "asks every open board to refresh after it is saved (DYN-01)" do
    expect { create(:alarm_call) }
      .to have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with("board", content: a_string_including('action="refresh"'))
  end
end
