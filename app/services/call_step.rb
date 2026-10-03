# One step in the life of a call (2.10, UPD-06 … UPD-12). The call and its car
# change together or not at all (STO-02); both rows are locked first, so two
# dispatchers cannot send one car at the same moment (STO-03).
class CallStep
  class Refused < StandardError; end
  # UPD-07, STO-03: the car is busy or out of service; the API answers 409.
  class Unavailable < Refused; end

  # UPD-11: the steps a dispatcher may take in each status, in their words.
  STEPS = { "pending" => %w[ Dispatch Cancel ], "dispatched" => %w[ Acceptance Arrival Cancel ],
            "accepted" => %w[ Arrival Cancel ], "on_scene" => %w[ Close ] }.freeze

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
    # CRW-04, CRW-06: the crew learns of it on its phones once the dispatch is
    # saved, and is reminded every minute until it accepts.
    CrewNoticeJob.perform_later(@call)
    CrewReminderJob.set(wait: 1.minute).perform_later(@call, 1)
  end

  # UPD-12: the crew has accepted the call, on its screen or by radio; the
  # car stays sent. A second acceptance, from a second phone or a second
  # tap, is taken as done already.
  def accept
    change(:accepted, @call.patrol_car) do
      @call.update!(status: :accepted, accepted_at: Time.current) unless @call.accepted?
    end
    "Call accepted by #{@call.patrol_car.call_sign}"
  end

  # An arrival without an acceptance is the acceptance too. The crew's step
  # comes with where its phone was (CRW-07).
  def arrive(position: nil)
    change(:on_scene, @call.patrol_car) do |car|
      now = Time.current
      @call.update!(status: :on_scene, arrived_at: now, accepted_at: @call.accepted_at || now)
      car.update!(status: :on_scene)
      record(:arrival, position)
    end
    "Arrival recorded; response time #{@call.response_minutes} min"
  end

  def close(outcome, note, position: nil)
    change(:closed, @call.patrol_car) do |car|
      raise Refused, "Choose an outcome to close the call" if outcome.blank?

      @call.update!(status: :closed, closed_at: Time.current, outcome:, description: noted("Closing note", note))
      car.update!(status: :available)
      record(:closing, position)
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

  # CRW-07: a step that comes with a position, the crew's, keeps it, known
  # or not; a step without one, the dispatcher's, keeps none.
  def record(step, position)
    return unless position

    @call.step_positions.create!(step:, user: @user, **StepPosition.reported(position, @call.guarded_site.address))
  end

  def refuse_order(status)
    return if @call.can_move_to?(status)
    return if status.to_s == "accepted" && @call.accepted?

    steps = STEPS[@call.status]
    raise Refused, "The call is #{@call.status}; no further steps" unless steps

    current = @call.status.humanize(capitalize: false)
    raise Refused, "Not possible for #{current.match?(/\A[aeiou]/) ? 'an' : 'a'} #{current} call; possible now: #{steps.join(', ')}"
  end

  def noted(label, text)
    return @call.description if text.blank?

    [ @call.description.presence, "#{label}: #{text}" ].compact.join("\n")
  end
end
