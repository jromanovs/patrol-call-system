# A further car sent to a call that has its car (BR-22). It has its own
# steps — sent, accepted, arrived — and is free again when the dispatcher
# releases it or the call ends; the call's own car closes the call.
class Backup < ApplicationRecord
  belongs_to :call
  belongs_to :patrol_car
  belongs_to :sent_by, class_name: "User"

  scope :active, -> { where(released_at: nil) }

  # DSP-03: every open board follows the further cars as it follows the calls.
  broadcasts_refreshes_to ->(_backup) { :board }

  # Where the car is, in the words the board uses for a call's own car; far
  # when its crew marked Arrived far from the place (CRW-09).
  def state
    if arrived_at then arrival_position&.far? ? "far" : "on-site"
    elsif accepted_at then "on-the-way"
    else "sent"
    end
  end

  # CRW-07: where the crew's phone was at Arrived; none when the dispatcher
  # recorded the arrival.
  def arrival_position = call.step_positions.find { |position| position.backup_id == id }
end
