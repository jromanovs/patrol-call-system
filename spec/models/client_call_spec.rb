require "rails_helper"

RSpec.describe ClientCall do
  subject { build(:client_call) }

  describe "validations" do
    it { is_expected.to validate_length_of(:caller_name).is_at_least(2).is_at_most(100) }
    it { is_expected.to allow_value("+37100000001", "+123456789012345").for(:caller_phone) }
    it { is_expected.not_to allow_value("12345", "+1234567", "+1234567890123456").for(:caller_phone) }
  end

  it "is a call made by the client by phone" do
    expect(described_class.superclass).to eq(Call)
  end

  it "starts with Normal priority (BR-2) and keeps a chosen one (ADD-07)", :aggregate_failures do
    expect(create(:client_call).priority).to eq("normal")
    expect(create(:client_call, priority: :critical).priority).to eq("critical")
  end

  it "describes itself for the board" do
    call = build(:client_call, caller_name: "Example Person", caller_phone: "+37100000005")

    expect([ call.summary, call.detail ]).to eq([ "Client call", "Example Person, +37100000005" ])
  end
end
