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

  describe ".search (FLT-07)" do
    include_context "with an empty address table"

    before do
      AddressRegisterLoad.new(file_fixture("aw_eka.csv")).call
    end

    def found(text) = described_class.search(text).map(&:full_address)

    it "finds every word regardless of letter case and Latvian diacritics", :aggregate_failures do
      expect(found("jekaba 11")).to eq([ "Jēkaba iela 11, Rīga, LV-1050" ])
      expect(found("BRĪVĪBAS 214")).to eq([ "Brīvības gatve 214, Rīga, LV-1039" ])
      expect(found("214 brivibas")).to eq([ "Brīvības gatve 214, Rīga, LV-1039" ])
    end

    it "orders by the full address" do
      expect(found("brivibas iela 10")).to eq([ "Brīvības iela 100, Rīga, LV-1001", "Brīvības iela 101, Rīga, LV-1001" ])
    end

    it "finds only existing addresses" do
      described_class.find_by!(code: 101_838_146).deleted!

      expect(found("jekaba")).to be_empty
    end

    it "does not search for fewer than 3 characters" do
      expect(found("ri")).to be_empty
    end

    it "takes % and _ literally" do
      expect(found("10%")).to be_empty
    end

    it "returns at most 10 addresses" do
      create_list(:address, 8, full_address: "Brīvības iela 5, Rīga, LV-1010")

      expect(described_class.existing.where("full_address LIKE ?", "Brīvības%").count).to eq(11)
      expect(found("brivibas").size).to eq(10)
    end
  end
end
