require "rails_helper"

RSpec.describe "Notices on the crew's phone (CRW-04, CRW-05)" do
  include_context "without the seeded records"

  let(:crew) { create(:user, :crew) }
  let(:endpoint) { "https://fcm.googleapis.com/fcm/send/phone-1" }
  # A subscription as the browser's PushSubscription.toJSON() gives it.
  let(:subscription) do
    { endpoint:, expirationTime: nil, keys: { p256dh: attributes_for(:push_subscription)[:p256dh], auth: "tBHItJI5svbpez7KI4CCXg==" } }
  end

  def subscribe(body = subscription) = post push_subscription_path, params: body, as: :json

  describe "turning notices on" do
    before { sign_in_as(crew) }

    it "keeps the phone for the crew user", :aggregate_failures do
      subscribe

      expect(response).to have_http_status(:created)
      expect(crew.push_subscriptions.sole).to have_attributes(endpoint:, auth: "tBHItJI5svbpez7KI4CCXg==",
                                                               p256dh: subscription.dig(:keys, :p256dh))
    end

    it "keeps one record of a phone sent again, for the user signed in on it now", :aggregate_failures do
      create(:push_subscription, endpoint:)

      expect { subscribe }.not_to change(PushSubscription, :count)
      expect(PushSubscription.find_by(endpoint:).user).to eq(crew)
    end

    it "refuses an unknown push service and stores nothing (CRW-05)", :aggregate_failures do
      subscribe(subscription.merge(endpoint: "https://example.com/push"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Endpoint is not the push service of a known browser")
      expect(PushSubscription.count).to eq(0)
    end

    it "refuses a subscription without its keys" do
      subscribe(subscription.except(:keys))

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "turning notices off" do
    before { sign_in_as(crew) }

    it "forgets the phone", :aggregate_failures do
      create(:push_subscription, user: crew, endpoint:)

      delete push_subscription_path, params: { endpoint: }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(PushSubscription.count).to eq(0)
    end

    it "leaves the phones of other users alone" do
      create(:push_subscription, endpoint:)

      expect { delete push_subscription_path, params: { endpoint: }, as: :json }.not_to change(PushSubscription, :count)
    end
  end

  it "refuses a user other than the crew and stores nothing (BR-14)", :aggregate_failures do
    sign_in_as(create(:user))

    subscribe

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to eq("Not allowed for your role")
    expect(PushSubscription.count).to eq(0)
  end

  it "leads to the sign-in page without a session" do
    subscribe

    expect(response).to redirect_to(new_session_path)
  end
end
