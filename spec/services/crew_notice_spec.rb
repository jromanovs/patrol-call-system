require "rails_helper"

RSpec.describe CrewNotice do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let(:site) do
    create(:guarded_site, name: "Demo Office 1", address: create(:address, full_address: "Jēkaba iela 11, Rīga, LV-1050"))
  end
  let(:call) { create(:alarm_call, guarded_site: site, priority: :critical) }
  let!(:phone) { create(:push_subscription, user: create(:user, :crew, patrol_car: car)) }
  let(:sent) { [] }

  before { allow(WebPush).to receive(:payload_send) { |**notice| sent << notice } }

  def dispatched = call.tap { CallStep.new(call, create(:user)).dispatch(car) }

  def crew_phone = create(:push_subscription, user: create(:user, :crew, patrol_car: car))

  describe "#deliver (CRW-04)" do
    it "sends the phone of the car's crew the call's priority, site and address, signed by the server", :aggregate_failures do
      described_class.new(dispatched).deliver

      notice = sent.sole
      expect(notice).to include(endpoint: phone.endpoint, p256dh: phone.p256dh, auth: phone.auth, ttl: 3600, urgency: "high")
      expect(notice[:vapid]).to eq(subject: "https://localhost", **described_class.keys)
      expect(JSON.parse(notice[:message], symbolize_names: true)).to eq(
        title: "Critical call: Demo Office 1",
        options: { body: "Jēkaba iela 11, Rīga, LV-1050", icon: "/icon-192.png", tag: "call-#{call.id}",
                   data: { path: "/crew" } })
    end

    it "names the system's own address as the sender in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.configuration).to receive(:hosts).and_return([ "patrol.example.org" ])
      allow(Rails.application.credentials).to receive(:web_push).and_return(public_key: "public", private_key: "private")

      described_class.new(dispatched).deliver

      expect(sent.sole[:vapid]).to eq(subject: "https://patrol.example.org", public_key: "public", private_key: "private")
    end

    it "sends every phone of the car's crew, and no other" do
      second = crew_phone
      create(:push_subscription)

      described_class.new(dispatched).deliver

      expect(sent.pluck(:endpoint)).to contain_exactly(phone.endpoint, second.endpoint)
    end

    it "sends nothing for a call no longer waiting for the car" do
      CallStep.new(dispatched, create(:user)).cancel("False alarm")

      described_class.new(call).deliver

      expect(sent).to be_empty
    end

    it "forgets a phone the push service no longer knows, and still sends the others", :aggregate_failures do
      second = crew_phone
      gone = Net::HTTPGone.new("1.1", "410", "Gone")
      allow(WebPush).to receive(:payload_send).with(hash_including(endpoint: phone.endpoint))
        .and_raise(WebPush::ExpiredSubscription.new(gone, "fcm.googleapis.com"))

      described_class.new(dispatched).deliver

      expect(PushSubscription.all).to contain_exactly(second)
      expect(sent.pluck(:endpoint)).to eq([ second.endpoint ])
    end

    it "keeps a phone whose push service fails for a while, and still sends the others", :aggregate_failures do
      second = crew_phone
      allow(WebPush).to receive(:payload_send).with(hash_including(endpoint: phone.endpoint)).and_raise(Net::OpenTimeout)

      expect { described_class.new(dispatched).deliver }.not_to raise_error
      expect(PushSubscription.all).to contain_exactly(phone, second)
      expect(sent.pluck(:endpoint)).to eq([ second.endpoint ])
    end
  end

  describe ".keys" do
    it "takes the server's key pair from the credentials" do
      allow(Rails.application.credentials).to receive(:web_push).and_return(public_key: "public", private_key: "private")

      expect(described_class.keys).to eq(public_key: "public", private_key: "private")
    end

    it "derives the same key pair every time outside production, one the push services accept", :aggregate_failures do
      keys = described_class.keys
      pair = WebPush::VapidKey.from_keys(keys[:public_key], keys[:private_key])

      expect(Base64.urlsafe_decode64(keys[:public_key]).bytesize).to eq(65)
      expect(pair.curve.check_key).to be(true)
      expect(described_class.keys).to eq(keys)
    end

    it "is never derived in production" do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect { described_class.keys }.to raise_error(RuntimeError, "web_push keys are missing in the production credentials")
    end
  end
end
