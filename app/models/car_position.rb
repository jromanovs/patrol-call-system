# TRK-03, BR-20: where a patrol car was, as the Traccar Client app on its
# crew's phone sent it; kept 30 days.
class CarPosition < ApplicationRecord
  KEPT = 30.days
  # A phone's clock may run ahead; beyond this its time is not believed.
  AHEAD = 5.minutes

  belongs_to :patrol_car

  validates :latitude, presence: true, numericality: { in: -90..90 }
  validates :longitude, presence: true, numericality: { in: -180..180 }
  validates :accuracy, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :recorded_at, presence: true

  # The newest position taken by each car within the 30 days, each found
  # through the car's own index rather than by reading all positions.
  def self.latest
    newest = sanitize_sql_array([ <<~SQL.squish, KEPT.ago ])
      SELECT newest.id FROM patrol_cars, LATERAL (SELECT id FROM car_positions
      WHERE car_positions.patrol_car_id = patrol_cars.id AND car_positions.recorded_at >= ?
      ORDER BY car_positions.recorded_at DESC LIMIT 1) newest
    SQL
    where("car_positions.id IN (#{newest})")
  end

  def self.prune = where(recorded_at: ...KEPT.ago).delete_all

  # API-11: the app's fields — lat, lon, accuracy in metres and timestamp in
  # seconds; without a believable timestamp, the time it arrived.
  def self.reported(fields)
    accuracy = Float(fields[:accuracy], exception: false)
    accuracy = nil unless accuracy&.between?(0, StepPosition::EARTH)
    { latitude: Float(fields[:lat], exception: false), longitude: Float(fields[:lon], exception: false),
      accuracy: accuracy&.round, recorded_at: taken_at(fields[:timestamp]) }
  end

  def self.taken_at(timestamp)
    seconds = Integer(timestamp, exception: false)
    now = Time.current
    seconds&.between?(0, (now + AHEAD).to_i) ? Time.zone.at(seconds) : now
  end
end
