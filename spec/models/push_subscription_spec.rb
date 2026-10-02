require "rails_helper"

RSpec.describe PushSubscription do
  subject(:phone) { build(:push_subscription) }

  include_context "without the seeded records"

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_uniqueness_of(:endpoint) }

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

  it "takes only keys as the browser gives them", :aggregate_failures do
    expect(build(:push_subscription, p256dh: "not a key")).not_to be_valid
    expect(build(:push_subscription, auth: "")).not_to be_valid
  end

  it "belongs to a crew user only (BR-14)", :aggregate_failures do
    phone.user = create(:user)

    expect(phone).not_to be_valid
    expect(phone.errors[:user]).to include("must be a crew user")
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
