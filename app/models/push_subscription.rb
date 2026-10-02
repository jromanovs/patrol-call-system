# CRW-04: a phone that receives the notices of its crew's car, as the push
# service of its browser knows it, for as long as the crew stays signed in on
# it (CRW-05).
class PushSubscription < ApplicationRecord
  # CRW-05: the push services of the browsers; the server sends notices to no
  # other address.
  SERVICES = %w[ fcm.googleapis.com push.apple.com push.services.mozilla.com notify.windows.com ].freeze
  CURVE = OpenSSL::PKey::EC::Group.new("prime256v1")

  belongs_to :session
  delegate :user, to: :session

  # Longer addresses than any push service gives would not fit the index.
  validates :endpoint, uniqueness: true, length: { maximum: 2048 }
  validate :known_service
  validate :phone_keys
  validate :crew_user

  scope :of_crew, ->(car) { joins(session: :user).where(users: { patrol_car_id: car, active: true }) }

  private

  def known_service
    host = service_host
    return if host && SERVICES.any? { |service| host == service || host.end_with?(".#{service}") }

    errors.add(:endpoint, "is not the push service of a known browser")
  end

  def service_host
    uri = URI.parse(endpoint.to_s)
    uri.host if uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    nil
  end

  # RFC 8291: the phone's public key is a point of the P-256 curve and its
  # secret 16 bytes; the sender could not encrypt a notice with anything else.
  def phone_keys
    errors.add(:p256dh, "is not the key of a phone") unless curve_point?(decoded(p256dh))
    errors.add(:auth, "is not the key of a phone") unless decoded(auth)&.bytesize == 16
  end

  def curve_point?(bytes)
    return false unless bytes&.bytesize == 65

    OpenSSL::PKey::EC::Point.new(CURVE, OpenSSL::BN.new(bytes, 2)).on_curve?
  rescue OpenSSL::PKey::EC::Point::Error
    false
  end

  # The keys come from the browser in URL-safe Base64, with or without padding.
  def decoded(key)
    Base64.urlsafe_decode64(key.to_s) if key.present?
  rescue ArgumentError
    nil
  end

  # BR-14: only a crew user turns notices on.
  def crew_user
    errors.add(:user, "must be a crew user") if session && !user.crew?
  end
end
