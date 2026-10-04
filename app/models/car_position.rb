# TRK-03, BR-20: where a patrol car was, as its position source sent it — the
# Traccar Client app or the crew screen of its crew's phone; kept for the
# period the administrator sets (TRK-05).
class CarPosition < ApplicationRecord
  # A car is shown, and its place taken for an SOS, at a position this fresh.
  SHOWN = 30.days
  # A phone's clock may run ahead; beyond this its time is not believed.
  AHEAD = 5.minutes

  belongs_to :patrol_car

  enum :source, PatrolCar.position_sources.except("not_tracked"), validate: true

  validates :latitude, presence: true, numericality: { in: -90..90 }
  validates :longitude, presence: true, numericality: { in: -180..180 }
  validates :accuracy, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :recorded_at, presence: true

  # The newest position taken by each car, by default within the 30 days,
  # each found through the car's own index rather than by reading all
  # positions; with no age asked for, of any age that is kept.
  def self.latest(since: SHOWN.ago)
    newest = sanitize_sql_array([ <<~SQL.squish, since || Time.zone.at(0) ])
      SELECT newest.id FROM patrol_cars, LATERAL (SELECT id FROM car_positions
      WHERE car_positions.patrol_car_id = patrol_cars.id AND car_positions.recorded_at >= ?
      ORDER BY car_positions.recorded_at DESC LIMIT 1) newest
    SQL
    where("car_positions.id IN (#{newest})")
  end

  # TRK-05: run once a night by CarPositionPruneJob. The period counts from
  # the day a position came: a phone's clock set to the past ends no record
  # early.
  def self.prune = where(created_at: ...Setting.current.kept.ago).delete_all

  # TRK-05: the day the oldest kept position came.
  def self.kept_since = minimum(:created_at)&.to_date

  # API-11: the app's fields — lat, lon, accuracy in metres and timestamp in
  # seconds; without a believable timestamp, the time it arrived.
  def self.reported(fields)
    place(fields[:lat], fields[:lon], fields[:accuracy]).merge(recorded_at: taken_at(fields[:timestamp]))
  end

  # TRK-04: what the crew screen sends, taken at the time it came.
  def self.from_phone(fields)
    place(fields[:latitude], fields[:longitude], fields[:accuracy]).merge(recorded_at: Time.current)
  end

  def self.place(latitude, longitude, accuracy)
    accuracy = Float(accuracy, exception: false)
    accuracy = nil unless accuracy&.between?(0, StepPosition::EARTH)
    { latitude: Float(latitude, exception: false), longitude: Float(longitude, exception: false),
      accuracy: accuracy&.round }
  end

  def self.taken_at(timestamp)
    seconds = Integer(timestamp, exception: false)
    now = Time.current
    seconds&.between?(0, (now + AHEAD).to_i) ? Time.zone.at(seconds) : now
  end
end
