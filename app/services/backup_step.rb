# The steps of a further car of a call (UPD-14 … UPD-16, BR-22). As with the
# call's own car (CallStep), the car and its record change together or not at
# all, and the call and the car are locked first, so that one free car is not
# sent to two calls at the same moment (STO-03).
class BackupStep
  # The statuses in which a call has its car.
  SERVED = %w[ dispatched accepted on_scene ].freeze

  def initialize(call, user)
    @call = call
    @user = user
  end

  def send_car(car)
    backup = change(car) do
      refuse_unserved
      raise CallStep::Unavailable, unavailable(car) unless car.available?
      raise CallStep::Refused, I18n.t("services.backup_step.own_car", car: car.call_sign) if car.id == @call.raised_by_id

      car.update!(status: :dispatched)
      @call.backups.create!(patrol_car: car, sent_by: @user, sent_at: Time.current)
    end
    # CRW-04: the crew of the further car learns of the call on its phones.
    CrewNoticeJob.perform_later(@call, car)
    backup
  end

  # A second acceptance, from a second phone or a second tap, changes nothing.
  def accept(backup)
    change(backup.patrol_car) do
      refuse_released(backup)
      backup.update!(accepted_at: Time.current) unless backup.accepted_at
    end
    I18n.t("services.backup_step.accepted", car: backup.patrol_car.call_sign)
  end

  # An arrival without an acceptance is the acceptance too; the crew's step
  # comes with where its phone was (CRW-07). A second arrival, from a second
  # phone or from a page not yet refreshed, changes nothing: the first time
  # and place stand, and with them the response time of the call.
  def arrive(backup, position: nil)
    change(backup.patrol_car) do |car|
      refuse_released(backup)
      next if backup.arrived_at

      now = Time.current
      backup.update!(arrived_at: now, accepted_at: backup.accepted_at || now)
      car.update!(status: :on_scene)
      record(backup, position)
    end
    I18n.t("services.backup_step.arrived", car: backup.patrol_car.call_sign)
  end

  def release(backup)
    change(backup.patrol_car) do |car|
      refuse_released(backup)
      backup.update!(released_at: Time.current)
      car.update!(status: :available)
    end
    I18n.t("services.backup_step.released", car: backup.patrol_car.call_sign)
  end

  # A further car goes only to a call that has its car and is not finished.
  def refuse_unserved
    return if @call.status.in?(SERVED)
    raise CallStep::Refused, I18n.t("services.backup_step.no_car_yet") if @call.pending?

    raise CallStep::Refused, CallStep.finished(@call)
  end

  private

  def change(car)
    Call.transaction do
      @call.lock!
      car.lock!
      yield car
    end
  rescue ActiveRecord::RecordInvalid => error
    raise CallStep::Refused, error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    raise CallStep::Unavailable, unavailable(car)
  end

  def unavailable(car) = I18n.t("services.call_step.unavailable", car: car.call_sign)

  def refuse_released(backup)
    return unless backup.reload.released_at

    raise CallStep::Refused, I18n.t("services.backup_step.already_released", car: backup.patrol_car.call_sign)
  end

  def record(backup, position)
    return unless position

    @call.step_positions.create!(step: :arrival, user: @user, backup:, **StepPosition.reported(position, @call.destination))
  end
end
