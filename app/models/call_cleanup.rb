# DEL-07, DEL-08: finished calls received before a day, chosen by status,
# call type and outcome, deleted together after a preview of their number.
class CallCleanup
  include ActiveModel::Model
  include ActiveModel::Attributes

  FINISHED = %w[ closed cancelled ].freeze
  Changed = Class.new(StandardError)

  attribute :before, :date
  attribute :statuses, default: -> { [] }
  attribute :kind, :string
  attribute :outcome, :string

  validate :day_chosen, :status_chosen

  def self.matching(count)
    case count
    when 0 then "No calls match"
    when 1 then "1 call matches"
    else "#{count} calls match"
    end
  end

  # Received before 00:00 Riga time of the day; never an active call (BR-8).
  def calls
    return Call.none unless before

    Call.where(status: chosen_statuses, received_at: ...before.in_time_zone)
        .where({ type: CallFilter::KINDS[kind], outcome: outcome.presence_in(Call.outcomes.keys) }.compact)
  end

  # What the preview hands to the confirmation: which calls matched then.
  def self.fingerprint(ids) = Digest::SHA256.hexdigest(ids.join(","))

  def ids = calls.order(:id).pluck(:id)

  # Exactly the calls the preview showed, or nothing. The rows are locked in
  # the order of their ids, so two clean-ups at once wait for each other.
  def delete(previewed)
    Call.transaction do
      ids = calls.order(:id).lock.pluck(:id)
      raise Changed, "#{self.class.matching(ids.size)} now" unless self.class.fingerprint(ids) == previewed

      StepPosition.where(call_id: ids).delete_all
      CallPhoto.where(call_id: ids).find_each(&:destroy!)
      Call.where(id: ids).delete_all
    end
  end

  private

  def chosen_statuses = Array(statuses) & FINISHED

  def day_chosen
    if before.nil?
      errors.add(:base, "Choose the day for Received before")
    elsif before > Time.zone.today
      errors.add(:base, "Received before cannot be in the future")
    end
  end

  def status_chosen
    errors.add(:base, "Choose closed, cancelled or both") if chosen_statuses.empty?
  end
end
