# CALC-01 … CALC-04 over the calls it is given, usually those of a
# CallFilter. A value that cannot be calculated is nil and shown as "—".
class CallStatistics
  include ActiveModel::Validations

  TOPS = 1..50
  DEFAULT_TOP = 5
  MINUTES = Arel.sql("EXTRACT(EPOCH FROM #{Call::FIRST_ARRIVAL} - calls.received_at) / 60")
  ACCEPTANCE = Arel.sql("EXTRACT(EPOCH FROM calls.accepted_at - calls.dispatched_at) / 60")
  OWN = Arel.sql("EXTRACT(EPOCH FROM calls.arrived_at - calls.received_at) / 60")
  FURTHER = Arel.sql("EXTRACT(EPOCH FROM backups.arrived_at - calls.received_at) / 60")

  FalseAlarms = Data.define(:count, :closed) do
    def share = closed.zero? ? nil : (count * 100.0 / closed).round(1)
  end

  validate :top_in_range

  # CALC-01: a filter without a period counts the current month in Riga time.
  def self.with_period(criteria)
    return criteria if criteria.key?("from") || criteria.key?("to")

    month = Time.zone.today.all_month
    criteria.merge("from" => month.first.iso8601, "to" => month.last.iso8601)
  end

  def initialize(calls, top: nil)
    @calls = calls
    @top = top.blank? ? DEFAULT_TOP : Integer(top.to_s, 10, exception: false)
  end

  def total = @calls.count

  def by_status = counted(:status, Call.statuses)

  def by_outcome = counted(:outcome, Call.outcomes)

  def arrivals = arrived.count

  def response = minutes(arrived.average(MINUTES))

  # CALC-02, 2.10: the accepted calls and the time from sending to acceptance.
  def acceptances = accepted.count

  def acceptance = minutes(accepted.average(ACCEPTANCE))

  # Each priority, critical first, with the number of arrivals and their average.
  def response_by_priority
    counts, averages = per(:priority)
    CallFilter::URGENCY.map { |priority| [ priority, counts.fetch(priority, 0), minutes(averages[priority]) ] }
  end

  # Every car with the number of its own arrivals, as the own car of a call
  # or as a further car (BR-22), and their average from the receipt of the call.
  def response_by_car
    arrivals = car_arrivals
    PatrolCar.order(:call_sign).map do |car|
      count, total = arrivals.fetch(car.id, [ 0, 0 ])
      [ car, count, (minutes(total / count) if count.positive?) ]
    end
  end

  def false_alarms
    closed = @calls.where(status: :closed)
    FalseAlarms.new(count: closed.where(outcome: :false_alarm).count, closed: closed.count)
  end

  def false_alarm_sites
    counts = @calls.where(outcome: :false_alarm).joins(:guarded_site).group("guarded_sites.id")
                   .order(Arel.sql("count(*) DESC"), "guarded_sites.name", "guarded_sites.id").limit(top).count
    GuardedSite.find(counts.keys).zip(counts.values)
  end

  def top = TOPS.cover?(@top) ? @top : DEFAULT_TOP

  private

  def arrived = @calls.where("#{Call::FIRST_ARRIVAL} IS NOT NULL")

  def accepted = @calls.where.not(accepted_at: nil).where.not(dispatched_at: nil)

  def per(column) = [ arrived.group(column).count, arrived.group(column).average(MINUTES) ]

  # Per car, how many times it arrived and the minutes those arrivals took.
  def car_arrivals
    own = @calls.where.not(arrived_at: nil).group(:patrol_car_id)
    further = Backup.joins(:call).where(call_id: @calls.select(:id)).where.not(arrived_at: nil).group("backups.patrol_car_id")
    [ [ own.count, own.sum(OWN) ], [ further.count, further.sum(FURTHER) ] ].each_with_object({}) do |(counts, totals), all|
      counts.each { |car, count| all[car] = all.fetch(car, [ 0, 0 ]).zip([ count, totals[car] ]).map(&:sum) }
    end
  end

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
