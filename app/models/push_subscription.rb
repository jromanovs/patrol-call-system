# CRW-04: a phone that receives the notices of its crew's car, as the push
# service of its browser knows it.
class PushSubscription < ApplicationRecord
  # CRW-05: the push services of the browsers; the server sends notices to no
  # other address.
  SERVICES = %w[ fcm.googleapis.com push.apple.com push.services.mozilla.com notify.windows.com ].freeze
  # The keys come from the browser in URL-safe Base64.
  KEY = /\A[A-Za-z0-9_-]+=*\z/

  belongs_to :user

  validates :endpoint, uniqueness: true
  validates :p256dh, :auth, format: { with: KEY }
  validate :known_service
  validate :crew_user

  scope :of_crew, ->(car) { joins(:user).where(users: { patrol_car_id: car, active: true }) }

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

  # BR-14: only a crew user turns notices on.
  def crew_user
    errors.add(:user, "must be a crew user") if user && !user.crew?
  end
end
