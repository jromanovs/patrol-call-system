# One step in the life of a call (2.10, UPD-06 … UPD-12). The call and its car
# change together or not at all (STO-02); both rows are locked first, so two
# dispatchers cannot send one car at the same moment (STO-03).
class CallStep
  class Refused < StandardError; end
  # UPD-07, STO-03: the car is busy or out of service; the API answers 409.
  class Unavailable < Refused; end

  # A closed or cancelled call takes no step; its status stands inside the
  # sentence, so its name begins with a small letter.
  def self.finished(call)
    I18n.t("services.call_step.finished", status: I18n.t("enums.call.status.#{call.status}").downcase_first)
  end

  def initialize(call, user)
    @call = call
    @user = user
  end

  def dispatch(car)
    change(:dispatched, car) do
      raise Unavailable, unavailable(car) unless car.available?

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
    I18n.t("services.call_step.accepted", car: @call.patrol_car.call_sign)
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
    I18n.t("services.call_step.arrived", minutes: @call.response_minutes)
  end

  def close(outcome, note, position: nil)
    change(:closed, @call.patrol_car) do |car|
      raise Refused, I18n.t("services.call_step.no_outcome") if outcome.blank?

      @call.update!(status: :closed, closed_at: Time.current, outcome:, closing_note: note.presence)
      car.update!(status: :available)
      record(:closing, position)
      free_backups
    end
  end

  def cancel(reason)
    change(:cancelled, @call.patrol_car) do |car|
      @call.update!(status: :cancelled, closed_at: Time.current, cancellation_reason: reason.presence)
      car&.update!(status: :available)
      free_backups
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
    raise Unavailable, unavailable(car)
  end

  def unavailable(car) = I18n.t("services.call_step.unavailable", car: car.call_sign)

  # CRW-07: a step that comes with a position, the crew's, keeps it, known
  # or not; a step without one, the dispatcher's, keeps none.
  def record(step, position)
    return unless position

    @call.step_positions.create!(step:, user: @user, **StepPosition.reported(position, @call.destination))
  end

  # UPD-16: the end of the call frees its further cars.
  def free_backups
    @call.backups.active.includes(:patrol_car).find_each do |backup|
      backup.patrol_car.lock!
      backup.update!(released_at: @call.closed_at)
      backup.patrol_car.update!(status: :available)
    end
  end

  def refuse_order(status)
    return if @call.can_move_to?(status)
    return if status.to_s == "accepted" && @call.accepted?

    raise Refused, self.class.finished(@call) unless @call.status.in?(Call::ACTIVE)

    # UPD-11: each status has its own sentence, with the steps possible in it.
    raise Refused, I18n.t("services.call_step.not_possible.#{@call.status}")
  end
end
