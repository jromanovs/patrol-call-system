# CRW-04: the notice of a new call on the phones of the car's crew. It goes
# through the push service of each phone's browser (RFC 8030), encrypted for
# the phone (RFC 8291) and signed with the server's key pair (VAPID, RFC 8292).
class CrewNotice
  # The server's key pair is missing from the production credentials, or
  # its two keys are not one pair.
  class Missing < StandardError; end

  # A notice waits this long for a phone that is offline.
  WAIT = 1.hour
  # How long one push service may take to connect, and to answer, so that
  # it never holds up the notices of the other phones.
  TIMEOUTS = { open_timeout: 10, read_timeout: 10 }.freeze
  # A phone the push service no longer knows.
  GONE = [ WebPush::ExpiredSubscription, WebPush::InvalidSubscription ].freeze
  # Failures of a push service or of the network that may pass; the phone is
  # kept for the next call.
  PASSING = [ WebPush::Error, Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError,
              Net::HTTPBadResponse, Net::ProtocolError ].freeze

  # The server's key pair, from the encrypted production credentials; outside
  # production one derived from the application's secret, the same every
  # time. Nil in production without both keys.
  def self.keys
    pair = Rails.application.credentials.web_push.to_h.slice(:public_key, :private_key)
    return pair if pair.size == 2 && pair.values.all?(&:present?)

    derived_keys unless Rails.env.production?
  end

# A broken key of the server must not look like phones that went away.
def self.one_pair?(keys)
  WebPush::VapidKey.from_keys(keys[:public_key], keys[:private_key]).curve.check_key
rescue OpenSSL::PKey::PKeyError, OpenSSL::PKey::EC::Point::Error, ArgumentError
  false
end

  def self.derived_keys
    secret = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("web_push", 32)
    point = OpenSSL::PKey::EC::Group.new("prime256v1").generator.mul(OpenSSL::BN.new(secret, 2))
    { public_key: Base64.urlsafe_encode64(point.to_octet_string(:uncompressed)), private_key: Base64.urlsafe_encode64(secret) }
  end

  # The contact that push services may use: the system's own address.
  def self.subject = "https://#{Rails.env.production? ? Rails.configuration.hosts.first : 'localhost'}"

  # A reminder (CRW-06) carries its number.
  def initialize(call, reminder: nil)
    @call = call
    @reminder = reminder
  end

  def deliver
    return unless @call.dispatched?

    keys = self.class.keys
    raise Missing, "web_push keys are missing in the production credentials" unless keys
    raise Missing, "web_push keys in the credentials are not one key pair" unless self.class.one_pair?(keys)

    vapid = { subject: self.class.subject, **keys }
    PushSubscription.of_crew(@call.patrol_car).find_each { |phone| send_to(phone, vapid) }
  end

  private

  def send_to(phone, vapid)
    WebPush.payload_send(message:, endpoint: phone.endpoint, p256dh: phone.p256dh, auth: phone.auth, vapid:,
                         ttl: WAIT.to_i, urgency: "high", **TIMEOUTS)
  rescue *GONE
    phone.destroy
  rescue *PASSING => error
    Rails.logger.warn("Crew notice of call #{@call.id} not sent through #{URI(phone.endpoint).host}: #{error.class}")
  end

  # The notice as the service worker shows it. A reminder has a tag of its
  # own: a phone that only replaces a notice does not sound again.
  def message = @message ||= notice.to_json

  def notice
    { title:, options: { body:, icon: ActionController::Base.helpers.image_path("icon-192.png"), tag:,
                         data: { path: Rails.application.routes.url_helpers.crew_path } } }
  end

  def title
    call = "#{@call.priority.humanize} call: #{@call.guarded_site.name}"
    @reminder ? "Reminder #{@reminder} — #{call}" : call
  end

  def body
    address = @call.guarded_site.address.full_address
    @reminder ? "#{address} · not accepted for #{@reminder} min" : address
  end

  def tag = [ "call-#{@call.id}", ("reminder-#{@reminder}" if @reminder) ].compact.join("-")
end
