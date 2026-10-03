# TRK-03, BR-20: where a patrol car was, as the Traccar Client app on its
# crew's phone sent it; kept 30 days.
class CarPosition < ApplicationRecord
  KEPT = 30.days

  belongs_to :patrol_car

  validates :latitude, presence: true, numericality: { in: -90..90 }
  validates :longitude, presence: true, numericality: { in: -180..180 }
  validates :accuracy, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :recorded_at, presence: true

  # The newest position of each car.
  def self.latest = select("DISTINCT ON (patrol_car_id) car_positions.*").order(:patrol_car_id, recorded_at: :desc)

  def self.prune = where(recorded_at: ...KEPT.ago).delete_all

  # API-11: the app's fields — lat, lon, accuracy in metres and timestamp in
  # seconds; without a timestamp, the time it arrived.
  def self.reported(fields)
    accuracy = Float(fields[:accuracy], exception: false)
    accuracy = nil unless accuracy&.between?(0, StepPosition::EARTH)
    seconds = Integer(fields[:timestamp], exception: false)
    { latitude: Float(fields[:lat], exception: false), longitude: Float(fields[:lon], exception: false),
      accuracy: accuracy&.round, recorded_at: seconds ? Time.zone.at(seconds) : Time.current }
  end
end
