require "rails_helper"

RSpec.describe StepPosition do
  subject(:position) { build(:step_position) }

  include_context "without the seeded records"

  it { is_expected.to belong_to(:call) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to define_enum_for(:step).with_values(arrival: 0, closing: 1) }

  it "takes a place on the earth, or no place at all (CRW-07)", :aggregate_failures do
    expect(position).to be_valid
    expect(build(:step_position, latitude: nil, longitude: nil, accuracy: nil, distance: nil)).to be_valid
    expect(build(:step_position, latitude: 91)).not_to be_valid
    expect(build(:step_position, longitude: -181)).not_to be_valid
    expect(build(:step_position, accuracy: -1)).not_to be_valid
  end

  it "keeps both coordinates or neither", :aggregate_failures do
    half = build(:step_position, longitude: nil)

    expect(half).not_to be_valid
    expect(half.errors[:base]).to include("Latitude and longitude come together")
  end

  it "measures the distance between two places in whole metres" do
    expect(described_class.distance(56.9512, 24.104642, 56.9522, 24.104642)).to eq(111)
  end

  it "goes with its call (BR-18)" do
    call = position.tap(&:save!).call
    call.update_column(:status, Call.statuses[:closed])

    expect { call.destroy }.to change(described_class, :count).by(-1)
  end
end
