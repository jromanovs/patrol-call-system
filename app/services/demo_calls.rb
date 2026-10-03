# STO-05: synthetic finished calls, one at a time, with steps that follow each
# other and outcomes that fit the kind of call. The shares and minutes are
# made up to give the statistics something to show; they are not measured.
class DemoCalls
  ALARMS = { "intrusion" => 35, "fire" => 10, "panic" => 10, "tamper" => 20, "power_failure" => 25 }.freeze
  CALLERS = [ "Example Person", "Sample Neighbour", "Test Resident", "Demo Caller" ].freeze
  # Minutes on the way to the site, by priority.
  TRAVEL = { "critical" => 4..10, "high" => 5..14, "normal" => 6..18, "low" => 8..25 }.freeze
  SIGNAL = { "fire_confirmed" => 2, "false_alarm" => 6, "technical_fault" => 2 }.freeze
  BREAK_IN = { "intrusion_confirmed" => 2, "false_alarm" => 13, "other" => 3 }.freeze
  FAULT = { "technical_fault" => 5, "false_alarm" => 4, "other" => 1 }.freeze
  OUTCOMES = { "fire" => SIGNAL, "intrusion" => BREAK_IN, "panic" => BREAK_IN, "tamper" => FAULT,
               "power_failure" => FAULT,
               "client" => { "other" => 5, "intrusion_confirmed" => 2, "false_alarm" => 3 } }.freeze
  CANCELLED = 0.12

  def initialize(random:, sites:, cars:, people:)
    @random = random
    @sites = sites
    @cars = cars
    @dispatcher, @supervisor = people
    @busy = Hash.new { |busy, car| busy[car] = [] }
    taken_already
  end

  # How long ago a call was received: within the days, and at least two
  # hours ago, so that every step is already over.
  def age(days) = (2.hours.to_i + @random.rand((days.days - 2.hours).to_i)).seconds

  def add(received_at)
    call = register(received_at)
    @random.rand < CANCELLED ? cancel(call) : close(call)
  end

  private

  def register(received_at)
    attributes = { guarded_site: pick(@sites), registered_by: @dispatcher, received_at: }
    if @random.rand < 0.75
      AlarmCall.create!(attributes.merge(alarm_type: weighted(ALARMS), sensor_zone: @random.rand(1..20)))
    else
      ClientCall.create!(attributes.merge(caller_name: pick(CALLERS), caller_phone: format("+37100000%03d", @random.rand(100..999)),
                                          priority: weighted("normal" => 3, "high" => 1)))
    end
  end

  def close(call)
    dispatched_at = call.received_at + minutes(1..6)
    arrived_at = dispatched_at + minutes(TRAVEL.fetch(call.priority))
    closed_at = arrived_at + minutes(10..45)
    car = free_car(dispatched_at..closed_at)
    return withdraw(call) unless car

    kind = call.is_a?(AlarmCall) ? call.alarm_type : "client"
    # 2.10: the crew accepts a minute after the dispatch, or on arrival.
    accepted_at = [ dispatched_at + 1.minute, arrived_at ].min
    call.update_columns(status: Call.statuses[:closed], **dispatch(car, dispatched_at), accepted_at:, arrived_at:, closed_at:,
                        outcome: Call.outcomes[weighted(OUTCOMES.fetch(kind))])
  end

  # Half before a car is sent, half after.
  def cancel(call)
    return withdraw(call) if @random.rand < 0.5

    dispatched_at = call.received_at + minutes(1..5)
    closed_at = dispatched_at + minutes(3..10)
    car = free_car(dispatched_at..closed_at)
    return withdraw(call) unless car

    call.update_columns(status: Call.statuses[:cancelled], **dispatch(car, dispatched_at), closed_at:)
  end

  # Cancelled before a car was sent; also when no car was free.
  def withdraw(call)
    call.update_columns(status: Call.statuses[:cancelled], closed_at: call.received_at + minutes(2..8))
  end

  # The calls the cars are or were on before the load; an active one lasts.
  def taken_already
    Call.where(patrol_car: @cars).where.not(dispatched_at: nil).pluck(:patrol_car_id, :dispatched_at, :closed_at)
        .each { |car, from, to| @busy[car] << (from..(to || Time.current + 1.year)) }
  end

  # A car is on one call at a time: one that has no call during the span.
  def free_car(span)
    free = @cars.reject { |car| @busy[car.id].any? { |taken| taken.begin < span.end && span.begin < taken.end } }
    pick(free).tap { |car| @busy[car.id] << span } if free.any?
  end

  def dispatch(car, at)
    { dispatched_at: at, patrol_car_id: car.id, dispatched_by_id: (@random.rand < 0.7 ? @dispatcher : @supervisor).id }
  end

  def minutes(range) = ((@random.rand(range) * 60) + @random.rand(60)).seconds

  def pick(list) = list[@random.rand(list.size)]

  def weighted(weights)
    point = @random.rand(weights.values.sum)
    weights.find { |_value, weight| (point -= weight).negative? }.first
  end
end
