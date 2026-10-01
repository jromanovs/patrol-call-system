# A call to the monitoring centre (2.6). Only the subclasses AlarmCall and
# ClientCall are saved; this class holds what they share.
class Call < ApplicationRecord
  ACTIVE = %w[ pending dispatched on_scene ].freeze

  belongs_to :guarded_site
  belongs_to :registered_by, class_name: "User"
  belongs_to :patrol_car, optional: true
  belongs_to :dispatched_by, class_name: "User", optional: true

  include StatusTransitions

  enum :priority, { low: 0, normal: 1, high: 2, critical: 3 }, validate: true
  enum :status, { pending: 0, dispatched: 1, on_scene: 2, closed: 3, cancelled: 4 }, validate: true
  enum :outcome, { false_alarm: 0, intrusion_confirmed: 1, fire_confirmed: 2, technical_fault: 3, other: 4 },
       validate: { allow_nil: true }

  transitions pending: %i[ dispatched cancelled ], dispatched: %i[ on_scene cancelled ], on_scene: :closed

  attribute :received_at, default: -> { Time.current }

  # DYN-01: every open board reloads its content after any change of a call.
  broadcasts_refreshes_to ->(_call) { :board }

  validates :type, presence: true
  validates :received_at, presence: true
  validates :description, length: { maximum: 1000 }
  validate :received_at_not_in_future
  validate :contract_active, on: :create
  validate :still_active, on: :update

  # DSP-03: critical first, then the longest wait.
  scope :on_board, -> { where(status: ACTIVE).order(priority: :desc, received_at: :asc) }

  def self.policy_class = CallPolicy

  def waiting_minutes(now = Time.current) = ((now - received_at) / 60).floor

  # 2.10: how long the client waited until the crew arrived.
  def response_minutes = arrived_at && ((arrived_at - received_at) / 60).round(1)

  # 2.10: how long the call took, or has taken so far while it is active.
  def handling_minutes(now = Time.current) = (((closed_at || now) - received_at) / 60).floor

  private

  def received_at_not_in_future
    errors.add(:received_at, "cannot be in the future") if received_at&.future?
  end

  # BR-1, ADD-08
  def contract_active
    return unless guarded_site&.suspended?

    errors.add(:base, "Contract #{guarded_site.contract_number} is suspended — call cannot be registered")
  end

  # BR-7
  def still_active
    errors.add(:base, "A closed or cancelled call cannot be changed") unless status_in_database.in?(ACTIVE)
  end
end
