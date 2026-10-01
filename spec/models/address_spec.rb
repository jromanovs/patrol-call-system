require "rails_helper"

RSpec.describe Address do
  subject { build(:address) }

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:code) }
    it { is_expected.to allow_value(101_000_034).for(:code) }
    it { is_expected.not_to allow_value(10_100_003, 1_010_000_340).for(:code) }
    it { is_expected.to validate_presence_of(:full_address) }
    it { is_expected.to allow_value("LV-4211", nil).for(:postal_code) }
    it { is_expected.not_to allow_value("4211", "LV-421").for(:postal_code) }
    it { is_expected.to validate_numericality_of(:latitude).is_in(55.6..58.1) }
    it { is_expected.to validate_numericality_of(:longitude).is_in(20.9..28.3) }
    it { is_expected.to define_enum_for(:status).with_values(existing: 0, deleted: 1, erroneous: 2) }
    it { is_expected.to validate_presence_of(:register_updated_on) }
  end

  it { is_expected.to have_many(:guarded_sites).dependent(:restrict_with_error) }

  it "starts as an existing address" do
    expect(described_class.new.status).to eq("existing")
  end
end
