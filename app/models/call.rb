# A call to the monitoring centre (2.6). Only the subclasses AlarmCall and
# ClientCall are saved; this class holds what they share.
class Call < ApplicationRecord
  ACTIVE = %w[ pending dispatched on_scene ].freeze

  belongs_to :guarded_site
  belongs_to :registered_by, class_name: "User"

  enum :priority, { low: 0, normal: 1, high: 2, critical: 3 }, validate: true
  enum :status, { pending: 0, dispatched: 1, on_scene: 2, closed: 3, cancelled: 4 }, validate: true

  attribute :received_at, default: -> { Time.current }

  # DYN-01: every open board reloads its content after any change of a call.
  broadcasts_refreshes_to ->(_call) { :board }

  validates :type, presence: true
  validates :received_at, presence: true
  validates :description, length: { maximum: 1000 }
  validate :received_at_not_in_future
  validate :contract_active, on: :create

  # DSP-03: critical first, then the longest wait.
  scope :on_board, -> { where(status: ACTIVE).order(priority: :desc, received_at: :asc) }

  def self.policy_class = CallPolicy

  def waiting_minutes(now = Time.current) = ((now - received_at) / 60).floor

  private

  def received_at_not_in_future
    errors.add(:received_at, "cannot be in the future") if received_at&.future?
  end

  # BR-1
  def contract_active
    errors.add(:guarded_site, "has a suspended contract") if guarded_site&.suspended?
  end
end
