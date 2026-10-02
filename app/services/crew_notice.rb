# CRW-04: the notice of a new call on the phones of the car's crew. It goes
# through the push service of each phone's browser (RFC 8030), encrypted for
# the phone (RFC 8291) and signed with the server's key pair (VAPID, RFC 8292).
class CrewNotice
  # A notice waits this long for a phone that is offline.
  WAIT = 1.hour
  # Failures of a push service that may pass; the phone is kept.
  PASSING = [ WebPush::Error, Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError ].freeze

  # The server's key pair, from the encrypted production credentials; outside
  # production one derived from the application's secret, the same every time.
  def self.keys
    Rails.application.credentials.web_push&.slice(:public_key, :private_key) || derived_keys
  end

  def self.derived_keys
    raise "web_push keys are missing in the production credentials" if Rails.env.production?

    secret = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("web_push", 32)
    point = OpenSSL::PKey::EC::Group.new("prime256v1").generator.mul(OpenSSL::BN.new(secret, 2))
    { public_key: Base64.urlsafe_encode64(point.to_octet_string(:uncompressed)), private_key: Base64.urlsafe_encode64(secret) }
  end

  # The contact that push services may use: the system's own address.
  def self.subject = "https://#{Rails.env.production? ? Rails.configuration.hosts.first : 'localhost'}"

  def initialize(call)
    @call = call
  end

  def deliver
    return unless @call.dispatched?

    vapid = { subject: self.class.subject, **self.class.keys }
    PushSubscription.of_crew(@call.patrol_car).find_each { |phone| send_to(phone, vapid) }
  end

  private

  def send_to(phone, vapid)
    WebPush.payload_send(message:, endpoint: phone.endpoint, p256dh: phone.p256dh, auth: phone.auth, vapid:,
                         ttl: WAIT.to_i, urgency: "high")
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    phone.destroy
  rescue *PASSING => error
    Rails.logger.warn("Crew notice of call #{@call.id} not sent through #{URI(phone.endpoint).host}: #{error.class}")
  end

  # The notice as the service worker shows it; a newer notice of the same
  # call replaces it.
  def message = @message ||= notice.to_json

  def notice
    site = @call.guarded_site
    { title: "#{@call.priority.humanize} call: #{site.name}",
      options: { body: site.address.full_address, icon: "/icon-192.png", tag: "call-#{@call.id}",
                 data: { path: Rails.application.routes.url_helpers.crew_path } } }
  end
end
