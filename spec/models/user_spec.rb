require "rails_helper"

RSpec.describe User do
  subject(:user) { build(:user) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_least(2).is_at_most(100) }
    it { is_expected.to validate_presence_of(:email_address) }
    it { is_expected.to validate_uniqueness_of(:email_address).case_insensitive }
    it { is_expected.to allow_value("dispatcher@example.com").for(:email_address) }
    it { is_expected.not_to allow_value("dispatcher").for(:email_address) }
    it { is_expected.to validate_length_of(:password).is_at_least(12) }
    it { is_expected.to validate_uniqueness_of(:google_uid).allow_nil }
    it { is_expected.to define_enum_for(:role).with_values(dispatcher: 0, supervisor: 1, administrator: 2, crew: 3) }
  end

  describe "the car of a crew (2.5)" do
    it "is required for the crew", :aggregate_failures do
      crew = build(:user, :crew, patrol_car: nil)

      expect(crew).not_to be_valid
      expect(crew.errors[:patrol_car]).to eq([ "must be chosen for a crew" ])
    end

    it "belongs to the crew only", :aggregate_failures do
      dispatcher = build(:user, patrol_car: create(:patrol_car))

      expect(dispatcher).not_to be_valid
      expect(dispatcher.errors[:patrol_car]).to eq([ "is only for a crew" ])
    end

    it "keeps a car with crew users from being deleted" do
      crew = create(:user, :crew)

      expect(crew.patrol_car.destroy).to be(false)
    end
  end

  it "starts as an active dispatcher", :aggregate_failures do
    expect(described_class.new.role).to eq("dispatcher")
    expect(described_class.new.active).to be(true)
  end

  it "stores the time of the last sign-in in UTC (BR-10)" do
    user = create(:user, last_signed_in_at: Time.utc(2026, 10, 1, 14, 12))

    stored = described_class.where(id: user.id).pick(Arel.sql("last_signed_in_at::text"))
    expect(stored).to eq("2026-10-01 14:12:00")
  end

  it "stores the e-mail address trimmed and in lower case" do
    user = create(:user, email_address: "  Dispatcher@Example.COM ")

    expect(user.email_address).to eq("dispatcher@example.com")
  end

  it "finds the user only with the right password", :aggregate_failures do
    user = create(:user, email_address: "a@example.com", password: "correct-horse-battery")

    expect(described_class.authenticate_by(email_address: "a@example.com", password: "correct-horse-battery")).to eq(user)
    expect(described_class.authenticate_by(email_address: "a@example.com", password: "wrong")).to be_nil
  end

  it "ends every session when the user is made inactive" do
    user = create(:user)
    user.sessions.create!

    expect { user.update!(active: false) }.to change(user.sessions, :count).from(1).to(0)
  end

  describe "the API key (USR-04, BR-13)" do
    let(:user) { create(:user) }

    it "is found by the key it issued, and only a digest of it is stored", :aggregate_failures do
      key = travel_to(Time.zone.local(2026, 10, 2, 10, 0)) { user.issue_api_key }

      expect(key.length).to be >= 40
      expect(described_class.find_by_api_key(key)).to eq(user)
      expect(user.reload.api_key_digest).not_to include(key)
      expect(user.api_key_issued_at).to eq(Time.zone.local(2026, 10, 2, 10, 0))
    end

    it "stops working when a new key is issued" do
      old_key = user.issue_api_key
      user.issue_api_key

      expect(described_class.find_by_api_key(old_key)).to be_nil
    end

    it "does not let an inactive user in, and the key stays void when the user is active again" do
      key = user.issue_api_key
      user.update!(active: false)
      user.update!(active: true)

      expect(described_class.find_by_api_key(key)).to be_nil
    end

    it "finds nobody for a missing or wrong key", :aggregate_failures do
      user.issue_api_key

      expect(described_class.find_by_api_key(nil)).to be_nil
      expect(described_class.find_by_api_key("")).to be_nil
      expect(described_class.find_by_api_key("wrong")).to be_nil
    end
  end
end
