# CRW-07, BR-18: where the crew's phone was at a step of a call, with its
# distance from the site; no coordinates when the phone gave none.
class StepPosition < ApplicationRecord
  # The mean radius of the earth, in metres.
  EARTH = 6_371_000
  # CRW-09: a step marked farther from the site than this, in metres, is a
  # warning to the dispatcher.
  FAR = 200

  belongs_to :call
  belongs_to :user
  # BR-22: the further car whose crew marked the step; none for the call's own car.
  belongs_to :backup, optional: true

  enum :step, { arrival: 0, closing: 1 }, validate: true

  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validates :accuracy, :distance, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validate :both_coordinates

  # The great-circle distance by the haversine formula, in whole metres.
  def self.distance(from_latitude, from_longitude, to_latitude, to_longitude)
    rise = radians(to_latitude - from_latitude)
    run = radians(to_longitude - from_longitude)
    a = (Math.sin(rise / 2)**2) +
        (Math.cos(radians(from_latitude)) * Math.cos(radians(to_latitude)) * (Math.sin(run / 2)**2))
    (2 * EARTH * Math.asin(Math.sqrt(a))).round
  end

  def self.radians(degrees) = degrees.to_f * Math::PI / 180

  # The place a phone sent, with its distance from the site's address, or
  # from the place of a crew's SOS when that is known, when it lies on the
  # earth; otherwise an unknown place.
  def self.reported(position, address)
    latitude = Float(position[:latitude], exception: false)
    longitude = Float(position[:longitude], exception: false)
    unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)
      return { latitude: nil, longitude: nil, accuracy: nil, distance: nil }
    end

    # An accuracy wider than the earth tells nothing.
    accuracy = Float(position[:accuracy], exception: false)
    accuracy = nil unless accuracy&.between?(0, EARTH)
    { latitude:, longitude:, accuracy: accuracy&.round,
      distance: address && distance(address.latitude, address.longitude, latitude, longitude) }
  end

  def known? = latitude.present?

  def far? = known? && distance.present? && distance > FAR

  private

  def both_coordinates
    errors.add(:base, :half_place) if latitude.nil? != longitude.nil?
  end
end
