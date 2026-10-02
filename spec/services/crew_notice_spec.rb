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
      expect(notice).to include(endpoint: phone.endpoint, p256dh: phone.p256dh, auth: phone.auth, ttl: 3600, urgency: "high",
                                open_timeout: 10, read_timeout: 10)
      expect(notice[:vapid]).to eq(subject: "https://localhost", **described_class.keys)
      expect(JSON.parse(notice[:message], symbolize_names: true)).to eq(
        title: "Critical call: Demo Office 1",
        options: { body: "Jēkaba iela 11, Rīga, LV-1050", icon: ActionController::Base.helpers.image_path("icon-192.png"),
                   tag: "call-#{call.id}",
                   data: { path: "/crew" } })
    end

    it "names the system's own address as the sender in production, with the credentials' keys" do
      pair = described_class.derived_keys
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.configuration).to receive(:hosts).and_return([ "patrol.example.org" ])
      allow(Rails.application.credentials).to receive(:web_push).and_return(pair)

      described_class.new(dispatched).deliver

      expect(sent.sole[:vapid]).to eq(subject: "https://patrol.example.org", **pair)
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

    # Answers of a push service, as the sender raises them.
    def answer(failure, response) = failure.new(instance_double(response, body: ""), "fcm.googleapis.com")

    # A phone the push service no longer knows (410, 404).
    { "a 410 answer" => -> { answer(WebPush::ExpiredSubscription, Net::HTTPGone) },
      "a 404 answer" => -> { answer(WebPush::InvalidSubscription, Net::HTTPNotFound) } }.each do |name, failure|
      it "forgets a phone on #{name}, and still sends the others", :aggregate_failures do
        second = crew_phone
        allow(WebPush).to receive(:payload_send).with(hash_including(endpoint: phone.endpoint)).and_raise(instance_exec(&failure))

        described_class.new(dispatched).deliver

        expect(PushSubscription.all).to contain_exactly(second)
        expect(sent.pluck(:endpoint)).to eq([ second.endpoint ])
      end
    end

    # Failures that may pass: of the push service (5xx, 429, 401) or of the network.
    { "a 503 answer" => -> { answer(WebPush::PushServiceError, Net::HTTPServiceUnavailable) },
      "a 429 answer" => -> { answer(WebPush::TooManyRequests, Net::HTTPTooManyRequests) },
      "a 401 answer" => -> { answer(WebPush::Unauthorized, Net::HTTPUnauthorized) },
      "no connection in time" => -> { Net::OpenTimeout.new }, "no answer in time" => -> { Net::ReadTimeout.new },
      "a broken connection" => -> { EOFError.new }, "a reset connection" => -> { Errno::ECONNRESET.new },
      "an unknown host" => -> { SocketError.new }, "a garbled answer" => -> { Net::HTTPBadResponse.new },
      "a TLS failure" => -> { OpenSSL::SSL::SSLError.new } }.each do |name, failure|
      it "keeps a phone on #{name}, and still sends the others", :aggregate_failures do
        second = crew_phone
        allow(WebPush).to receive(:payload_send).with(hash_including(endpoint: phone.endpoint)).and_raise(instance_exec(&failure))

        expect { described_class.new(dispatched).deliver }.not_to raise_error
        expect(PushSubscription.all).to contain_exactly(phone, second)
        expect(sent.pluck(:endpoint)).to eq([ second.endpoint ])
      end
    end

    it "fails, so the failure is recorded among the failed jobs, without the server's keys in production" do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect { described_class.new(dispatched).deliver }
      .to raise_error(CrewNotice::Missing, "web_push keys are missing in the production credentials")
  end

  it "keeps every phone and fails when the server's keys are not one pair", :aggregate_failures do
    other = OpenSSL::PKey::EC.generate("prime256v1").public_key.to_octet_string(:uncompressed)
    allow(described_class).to receive(:keys)
      .and_return(public_key: Base64.urlsafe_encode64(other), private_key: described_class.derived_keys[:private_key])

    expect { described_class.new(dispatched).deliver }
      .to raise_error(CrewNotice::Missing, "web_push keys in the credentials are not one key pair")
    expect([ PushSubscription.all, sent ]).to eq([ [ phone ], [] ])
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

    it "is never derived in production, and a half pair counts as none", :aggregate_failures do
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.keys).to be_nil

      allow(Rails.application.credentials).to receive(:web_push).and_return(public_key: "public")
      expect(described_class.keys).to be_nil
    end
  end
end
