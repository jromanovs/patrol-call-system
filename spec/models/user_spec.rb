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
    it { is_expected.to define_enum_for(:theme).with_values(system: 0, light: 1, dark: 2).with_prefix }
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

    it "is held by the database too: a crew user without a car is refused" do
      crew = create(:user, :crew)

      expect { crew.update_column(:patrol_car_id, nil) }.to raise_error(ActiveRecord::StatementInvalid, /users_car_only_for_crew/)
    end

    it "keeps a car with crew users from being deleted" do
      crew = create(:user, :crew)

      expect(crew.patrol_car.destroy).to be(false)
    end
  end

  it "starts with the theme of the device, and takes no theme but the three (USR-09)", :aggregate_failures do
    expect(described_class.new.theme).to eq("system")
    expect(build(:user, theme: "sepia")).not_to be_valid
    expect(build(:user, theme: nil)).not_to be_valid
  end

  it "has no language until one is chosen, and takes none but the system's (USR-10)", :aggregate_failures do
    expect(described_class.new.locale).to be_nil
    expect(build(:user, locale: "lv")).to be_valid
    expect(build(:user, locale: "de")).not_to be_valid
    expect(build(:user, locale: "")).not_to be_valid
  end

  it "is held to the languages of the system by the database too" do
    user = create(:user)

    expect { user.update_column(:locale, "de") }.to raise_error(ActiveRecord::StatementInvalid, /users_locale/)
  end

  it "is held to the three themes by the database too" do
    user = create(:user)

    expect { user.update_column(:theme, 3) }.to raise_error(ActiveRecord::StatementInvalid, /users_theme/)
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

  # A refusal that first deleted the sessions would leave them deleted when the
  # deletion runs inside a wider transaction: nothing rolls them back there.
  it "refuses to delete a user whom a call keeps before it touches the user's sessions (USR-03)", :aggregate_failures do
    user = create(:alarm_call).registered_by
    user.sessions.create!

    expect { described_class.transaction { user.destroy } }.not_to change(Session, :count)
    expect(user.errors[:base]).to be_present
  end

  describe "the picture (USR-07)" do
    let(:photo) { { io: file_fixture("photo.jpg").open, filename: "photo.jpg" } }

    it "stays with a user whose deletion is refused, also inside a wider transaction", :aggregate_failures do
      user = create(:alarm_call).registered_by
      user.update!(avatar: photo)

      expect { described_class.transaction { user.destroy } }.not_to have_enqueued_job(ActiveStorage::PurgeJob)
      expect(user.reload.avatar).to be_attached
    end

    it "goes with a user who is deleted, its file queued for removal", :aggregate_failures do
      user = create(:user, avatar: photo)

      expect { user.destroy }.to have_enqueued_job(ActiveStorage::PurgeJob).exactly(:once)
      expect(ActiveStorage::Attachment.count).to eq(0)
    end

    it "is taken away by a save that sets none, without a word about its kind" do
      user = create(:user, avatar: photo)

      expect(user.update(avatar: nil)).to be(true)
    end
  end

  describe "the sessions of a user whose password changes (USR-02, USR-06)" do
    let(:user) { create(:user) }

    before { 2.times { user.sessions.create! } }

    after { Current.reset }

    it "end, all of them, when nobody's session saved the change" do
      expect { user.update!(password: "another-long-password") }.to change(user.sessions, :count).from(2).to(0)
    end

    it "end but the one that saved the change, when it is the user's own", :aggregate_failures do
      Current.session = user.sessions.first
      user.update!(password: "another-long-password")

      expect(user.sessions.ids).to eq([ Current.session.id ])
    end

    it "end, all of them, when the session of another user saved the change" do
      Current.session = create(:user, :administrator).sessions.create!

      expect { user.update!(password: "another-long-password") }.to change(user.sessions, :count).from(2).to(0)
    end

    it "stay when anything else of the user changes", :aggregate_failures do
      expect { user.update!(name: "Demo Supervisor", role: :supervisor) }.not_to change(Session, :count)
      expect { user.issue_api_key }.not_to change(Session, :count)
    end

    it "stay when the change is refused" do
      expect { user.update(password: "short") }.not_to change(Session, :count)
    end

    # One step with the change: both are kept or neither, so that no failure
    # in between leaves a new password with the old sessions.
    it "end in the same transaction as the change", :aggregate_failures do
      described_class.transaction do
        user.update!(password: "another-long-password")
        expect(user.sessions.count).to eq(0)
        raise ActiveRecord::Rollback
      end

      expect(user.sessions.count).to eq(2)
      expect(user.reload.authenticate("another-long-password")).to be(false)
    end
  end

  describe "the API key of a user whose password changes (BR-13)" do
    let(:user) { create(:user, password: "correct-horse-battery") }
    let!(:key) { user.issue_api_key }
    let(:typed) { { password: "another-long-password", confirmation: "another-long-password" } }

    it "is void when an administrator sets the password, and is not said to be issued", :aggregate_failures do
      user.set_password(**typed)

      expect(described_class.find_by_api_key(key)).to be_nil
      expect(user.reload.api_key_issued_at).to be_nil
    end

    it "is void when the user changes their own" do
      user.change_password(current: "correct-horse-battery", **typed)

      expect(described_class.find_by_api_key(key)).to be_nil
    end

    it "stays when the change is refused, and when anything else of the user changes", :aggregate_failures do
      expect(user.set_password(password: "short", confirmation: "short")).to be(false)
      expect(described_class.find(user.id).change_password(current: "wrong", **typed)).to be(false)
      described_class.find(user.id).update!(name: "Demo Supervisor", role: :supervisor, password: "")

      expect(described_class.find_by_api_key(key)).to eq(user)
    end

    # One step with the change: both are kept or neither, so that no failure
    # in between leaves a new password with the old key.
    it "is void in the same transaction as the change", :aggregate_failures do
      described_class.transaction do
        user.update!(password: "another-long-password")
        expect(described_class.find_by_api_key(key)).to be_nil
        raise ActiveRecord::Rollback
      end

      expect(described_class.find_by_api_key(key)).to eq(user)
    end
  end

  describe "the Google account of a user whose address changes (BR-15)" do
    let!(:user) { create(:user, email_address: "dispatcher@example.com", google_uid: "google-123") }

    # One step with the change: no failure in between leaves the new address
    # with the account of the old one.
    it "is forgotten in the same transaction as the change", :aggregate_failures do
      described_class.transaction do
        user.update!(email_address: "other@example.com")
        expect(described_class.find(user.id).google_uid).to be_nil
        raise ActiveRecord::Rollback
      end

      expect(user.reload.google_uid).to eq("google-123")
    end

    it "stays when the change is refused, and when the same address is written otherwise", :aggregate_failures do
      expect(user.update(email_address: "not-an-address")).to be(false)
      described_class.find(user.id).update!(email_address: "  Dispatcher@Example.COM ")

      expect(user.reload.google_uid).to eq("google-123")
    end

    it "stays when anything else of the user changes" do
      user.update!(name: "Demo Supervisor", role: :supervisor, password: "another-long-password", active: false)

      expect(user.reload.google_uid).to eq("google-123")
    end
  end

  describe "a password set for the user by an administrator (USR-08)" do
    let(:user) { create(:user, password: "correct-horse-battery") }

    it "takes the new password typed twice" do
      expect(user.set_password(password: "another-long-password", confirmation: "another-long-password")).to be(true)
    end

    it "refuses none, one that is not repeated, and nil for either: nil is never a way round a check", :aggregate_failures do
      [ { password: "", confirmation: "" }, { password: nil, confirmation: "another-long-password" },
        { password: "another-long-password", confirmation: nil }, { password: "another-long-password", confirmation: "" } ].each do |typed|
        expect(user.reload.set_password(**typed)).to be(false), typed.inspect
      end
      expect(user.reload.authenticate("correct-horse-battery")).to be_truthy
    end
  end

  describe "the user's own change of the password (USR-06)" do
    let(:user) { create(:user, password: "correct-horse-battery") }
    let(:typed) { { current: "correct-horse-battery", password: "another-long-password", confirmation: "another-long-password" } }

    it "takes the current password and the new one twice" do
      expect(user.change_password(**typed)).to be(true)
    end

    it "refuses when any of the three is nil: nil is never a way round a check", :aggregate_failures do
      typed.each_key do |missing|
        expect(user.reload.change_password(**typed, missing => nil)).to be(false), missing.to_s
      end
      expect(user.reload.authenticate("correct-horse-battery")).to be_truthy
    end

    it "leaves an administrator's edit free to keep the password as it is" do
      expect(user.update(name: "Demo Supervisor", password: "")).to be(true)
    end
  end
end
