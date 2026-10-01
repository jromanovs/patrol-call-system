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

    errors.add(:status, "cannot change from #{from.humanize(capitalize: false)} to #{status.humanize(capitalize: false)}")
  end
end
