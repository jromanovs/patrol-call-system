# CALC-01 … CALC-04 over the calls it is given, usually those of a
# CallFilter. A value that cannot be calculated is nil and shown as "—".
class CallStatistics
  include ActiveModel::Validations

  TOPS = 1..50
  DEFAULT_TOP = 5
  MINUTES = Arel.sql("EXTRACT(EPOCH FROM calls.arrived_at - calls.received_at) / 60")

  FalseAlarms = Data.define(:count, :closed) do
    def share = closed.zero? ? nil : (count * 100.0 / closed).round(1)
  end

  validate :top_in_range

  def initialize(calls, top: nil)
    @calls = calls
    @top = top.blank? ? DEFAULT_TOP : Integer(top.to_s, 10, exception: false)
  end

  def total = @calls.count

  def by_status = counted(:status, Call.statuses)

  def by_outcome = counted(:outcome, Call.outcomes)

  def arrivals = arrived.count

  def response = minutes(arrived.average(MINUTES))

  # Each priority, critical first, with the number of arrivals and their average.
  def response_by_priority
    counts, averages = per(:priority)
    CallFilter::URGENCY.map { |priority| [ priority, counts.fetch(priority, 0), minutes(averages[priority]) ] }
  end

  # Every car with the number of its arrivals and their average.
  def response_by_car
    counts, averages = per(:patrol_car_id)
    PatrolCar.order(:call_sign).map { |car| [ car, counts.fetch(car.id, 0), minutes(averages[car.id]) ] }
  end

  def false_alarms
    closed = @calls.where(status: :closed)
    FalseAlarms.new(count: closed.where(outcome: :false_alarm).count, closed: closed.count)
  end

  def false_alarm_sites
    counts = @calls.where(outcome: :false_alarm).joins(:guarded_site).group("guarded_sites.id")
                   .order(Arel.sql("count(*) DESC"), "guarded_sites.name").limit(top).count
    GuardedSite.find(counts.keys).zip(counts.values)
  end

  def top = TOPS.cover?(@top) ? @top : DEFAULT_TOP

  private

  def arrived = @calls.where.not(arrived_at: nil)

  def per(column) = [ arrived.group(column).count, arrived.group(column).average(MINUTES) ]

  # Every value of the enumeration in the alphabet of its name, with zeros.
  def counted(attribute, values)
    counts = @calls.group(attribute).count
    values.keys.sort_by(&:humanize).map { |value| [ value, counts.fetch(value, 0) ] }
  end

  def minutes(average) = average&.round(1)&.to_f

  def top_in_range
    errors.add(:base, "Number of sites must be from #{TOPS.min} to #{TOPS.max}") unless TOPS.cover?(@top)
  end
end
