# The interface shared by Call and PatrolCar: which status may follow which
# (2.10, BR-5). A record refuses a status change that its table does not allow.
module StatusTransitions
  extend ActiveSupport::Concern

  included do
    class_attribute :status_transitions, instance_writer: false, default: {}
    validate :allowed_transition, on: :update, if: :will_save_change_to_status?
  end

  class_methods do
    def transitions(table)
      self.status_transitions = table.to_h { |from, to| [ from.to_s, Array(to).map(&:to_s) ] }
    end

    def next_statuses(from) = status_transitions.fetch(from.to_s, [])
  end

  def next_statuses = self.class.next_statuses(status)

  def can_move_to?(status) = next_statuses.include?(status.to_s)

  private

  def allowed_transition
    from = status_in_database
    return if self.class.next_statuses(from).include?(status)

    errors.add(:status, :not_next, from: status_word(from), to: status_word(status))
  end

  # The name of a status as it stands inside a sentence. Subclasses share the
  # names of their base class.
  def status_word(status)
    I18n.t("enums.#{self.class.base_class.model_name.i18n_key}.status.#{status}").downcase_first
  end
end
