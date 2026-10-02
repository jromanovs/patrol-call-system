# One step in the life of a call (2.10, UPD-06 … UPD-11). The call and its car
# change together or not at all (STO-02); both rows are locked first, so two
# dispatchers cannot send one car at the same moment (STO-03).
class CallStep
  class Refused < StandardError; end
  # UPD-07, STO-03: the car is busy or out of service; the API answers 409.
  class Unavailable < Refused; end

  # UPD-11: the steps a dispatcher may take in each status, in their words.
  STEPS = { "pending" => %w[ Dispatch Cancel ], "dispatched" => %w[ Arrival Cancel ], "on_scene" => %w[ Close ] }.freeze

  def initialize(call, user)
    @call = call
    @user = user
  end

  def dispatch(car)
    change(:dispatched, car) do
      raise Unavailable, "Car #{car.call_sign} is not available" unless car.available?

      @call.update!(status: :dispatched, dispatched_at: Time.current, patrol_car: car, dispatched_by: @user)
      car.update!(status: :dispatched)
    end
  end

  def arrive
    change(:on_scene, @call.patrol_car) do |car|
      @call.update!(status: :on_scene, arrived_at: Time.current)
      car.update!(status: :on_scene)
    end
    "Arrival recorded; response time #{@call.response_minutes} min"
  end

  def close(outcome, note)
    change(:closed, @call.patrol_car) do |car|
      raise Refused, "Choose an outcome to close the call" if outcome.blank?

      @call.update!(status: :closed, closed_at: Time.current, outcome:, description: noted("Closing note", note))
      car.update!(status: :available)
    end
  end

  def cancel(reason)
    change(:cancelled, @call.patrol_car) do |car|
      @call.update!(status: :cancelled, closed_at: Time.current, description: noted("Cancelled", reason))
      car&.update!(status: :available)
    end
  end

  private

  def change(status, car)
    Call.transaction do
      @call.lock!
      car&.lock!
      refuse_order(status)
      yield car
    end
  rescue ActiveRecord::RecordInvalid => error
    raise Refused, error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    raise Unavailable, "Car #{car.call_sign} is not available"
  end

  def refuse_order(status)
    return if @call.can_move_to?(status)

    steps = STEPS[@call.status]
    raise Refused, "The call is #{@call.status}; no further steps" unless steps

    raise Refused, "Not possible for a #{@call.status.humanize(capitalize: false)} call; possible now: #{steps.join(', ')}"
  end

  def noted(label, text)
    return @call.description if text.blank?

    [ @call.description.presence, "#{label}: #{text}" ].compact.join("\n")
  end
end
