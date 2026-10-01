require "rails_helper"

RSpec.describe GuardedSite do
  subject { build(:guarded_site) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:contract_number) }
    it { is_expected.to validate_uniqueness_of(:contract_number).case_insensitive }
    it { is_expected.to allow_value("C-00042").for(:contract_number) }
    it { is_expected.not_to allow_value("C-0042", "X-00042", "C-000420").for(:contract_number) }
    it { is_expected.to validate_length_of(:name).is_at_least(2).is_at_most(100) }
    it { is_expected.to validate_length_of(:client_name).is_at_least(2).is_at_most(100) }
    it { is_expected.to belong_to(:address) }
    it { is_expected.to define_enum_for(:site_type).with_values(apartment: 0, house: 1, office: 2, shop: 3, warehouse: 4) }
    it { is_expected.to define_enum_for(:district).with_values(centre: 0, north: 1, south: 2, east: 3, west: 4) }
    it { is_expected.to define_enum_for(:contract_status).with_values(active: 0, suspended: 1) }
    it { is_expected.to allow_value("+37100000001", "+123456789012345").for(:keyholder_phone) }
    it { is_expected.not_to allow_value("37100000001", "+1234567", "+1234567890123456").for(:keyholder_phone) }
    it { is_expected.to validate_presence_of(:contract_start_date) }
    it { is_expected.to validate_length_of(:access_notes).is_at_most(500) }
  end

  it { is_expected.to have_many(:calls).dependent(:restrict_with_error) }

  it "starts with an active contract" do
    expect(described_class.new.contract_status).to eq("active")
  end

  it "refuses a date that is not on the calendar" do
    site = build(:guarded_site, contract_start_date: "2026-02-31")

    expect(site).not_to be_valid
  end

  it "accepts only an address the register marks existing (BR-11)" do
    site = build(:guarded_site, address: build(:address, status: :deleted))

    expect(site).not_to be_valid
    expect(site.errors[:address]).to include("is not an existing address in the register")
  end

  it "keeps its address when the register later marks it deleted (BR-12)" do
    site = create(:guarded_site)
    site.address.update!(status: :deleted)

    expect(site.reload).to be_valid
  end
end
