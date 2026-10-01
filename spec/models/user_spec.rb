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
    it { is_expected.to define_enum_for(:role).with_values(dispatcher: 0, supervisor: 1, administrator: 2) }
  end

  it "starts as an active dispatcher", :aggregate_failures do
    expect(described_class.new.role).to eq("dispatcher")
    expect(described_class.new.active).to be(true)
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
end
