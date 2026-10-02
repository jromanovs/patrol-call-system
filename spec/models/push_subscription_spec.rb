require "rails_helper"

RSpec.describe PushSubscription do
  subject(:phone) { build(:push_subscription) }

  include_context "without the seeded records"

  it { is_expected.to belong_to(:session) }
  it { is_expected.to validate_uniqueness_of(:endpoint) }
  it { is_expected.to validate_length_of(:endpoint).is_at_most(2048) }

  describe "the push service (CRW-05)" do
    it "takes the push services of the browsers", :aggregate_failures do
      %w[ https://fcm.googleapis.com/fcm/send/a https://web.push.apple.com/b
          https://updates.push.services.mozilla.com/wpush/v2/c https://wns2-par02p.notify.windows.com/w/?token=d ]
        .each { |endpoint| expect(build(:push_subscription, endpoint:)).to be_valid, endpoint }
    end

    it "refuses any other address", :aggregate_failures do
      [ "http://fcm.googleapis.com/fcm/send/a", "https://example.com/push", "https://fcm.googleapis.com.example.com/a",
        "https://localhost/push", "not an address", "" ].each do |endpoint|
        other = build(:push_subscription, endpoint:)
        expect(other).not_to be_valid, endpoint
        expect(other.errors[:endpoint]).to include("is not the push service of a known browser")
      end
    end
  end

  describe "the phone's keys" do
    it "takes a P-256 public key and a 16-byte secret, with or without padding", :aggregate_failures do
      expect(phone).to be_valid
      expect(build(:push_subscription, auth: "1ffQLSTcbgN38YNDstaf7w==")).to be_valid
    end

    it "refuses anything the sender could not read", :aggregate_failures do
      off_curve = Base64.urlsafe_encode64("\x04".b + ("\x01".b * 64), padding: false)
      [ "not a key", "", "AAAA", off_curve, "AQ" * 43 ].each do |p256dh|
        other = build(:push_subscription, p256dh:)
        expect(other).not_to be_valid, p256dh
        expect(other.errors[:p256dh]).to include("is not the key of a phone")
      end
      other = build(:push_subscription, auth: "AAAA")
      expect(other).not_to be_valid
      expect(other.errors[:auth]).to include("is not the key of a phone")
    end
  end

  it "belongs to the sign-in of a crew user only (BR-14)", :aggregate_failures do
    phone.session = create(:user).sessions.create!

    expect(phone).not_to be_valid
    expect(phone.errors[:user]).to include("must be a crew user")
  end

  it "ends with the sign-in on the phone (CRW-05)" do
    phone.save!

    expect { phone.session.destroy }.to change(described_class, :count).by(-1)
  end

  describe ".of_crew" do
    let(:car) { create(:patrol_car) }
    let!(:crew_phone) { create(:push_subscription, user: create(:user, :crew, patrol_car: car)) }

    before do
      create(:push_subscription, user: create(:user, :crew, patrol_car: car, active: false))
      create(:push_subscription)
    end

    it "holds the phones of the car's active crew users" do
      expect(described_class.of_crew(car)).to contain_exactly(crew_phone)
    end
  end
end
