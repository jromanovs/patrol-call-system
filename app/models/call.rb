# A call to the monitoring centre (2.6). Only the subclasses AlarmCall,
# ClientCall and SosCall are saved; this class holds what they share.
class Call < ApplicationRecord
  ACTIVE = %w[ pending dispatched accepted on_scene ].freeze
  # CRW-06: the reminders of a call not accepted, one a minute; after the
  # last the call shows as unanswered.
  REMINDERS = 5
  # 2.10: when the first car arrived, the call's own or a further one.
  FIRST_ARRIVAL = "LEAST(calls.arrived_at, (SELECT MIN(backups.arrived_at) FROM backups " \
                  "WHERE backups.call_id = calls.id))".freeze

  # BR-21: a crew's SOS has no site and, sent by a phone, nobody who
  # registered it; every other call has both.
  belongs_to :guarded_site, optional: true
  belongs_to :registered_by, class_name: "User", optional: true
  belongs_to :patrol_car, optional: true
  belongs_to :dispatched_by, class_name: "User", optional: true
  # BR-21: the car that asks for help, and who saw its signal.
  belongs_to :raised_by, class_name: "PatrolCar", optional: true
  belongs_to :acknowledged_by, class_name: "User", optional: true
  # CRW-07, BR-18: where the crew's phone was at its steps, gone with the call.
  has_many :step_positions, dependent: :delete_all
  # BR-22: the further cars sent to the call, gone with it.
  has_many :backups, dependent: :delete_all
  # CRW-10, BR-19: the crew's photos, their files gone with them.
  has_many :photos, class_name: "CallPhoto", dependent: :destroy

  include StatusTransitions

  enum :priority, { low: 0, normal: 1, high: 2, critical: 3 }, validate: true
  # Accepted came later; its value is new, its place is in the order of the life of a call.
  enum :status, { pending: 0, dispatched: 1, accepted: 5, on_scene: 2, closed: 3, cancelled: 4 }, validate: true
  enum :outcome, { false_alarm: 0, intrusion_confirmed: 1, fire_confirmed: 2, technical_fault: 3, other: 4,
                   help_given: 5 }, validate: { allow_nil: true }

  transitions pending: %i[ dispatched cancelled ], dispatched: %i[ accepted on_scene cancelled ],
              accepted: %i[ on_scene cancelled ], on_scene: :closed

  attribute :received_at, default: -> { Time.current }

  # DYN-01: every open board reloads its content after any change of a call.
  broadcasts_refreshes_to ->(_call) { :board }

  validates :type, presence: true
  validates :guarded_site, :registered_by, presence: { message: "must exist" }, if: :at_site?
  validates :received_at, presence: true
  validates :description, length: { maximum: 1000 }
  validate :received_at_not_in_future
  validate :outcome_of_its_kind
  validate :contract_active, on: :create
  validate :still_active, on: :update
  # Before the records of the call go: a refusal must not have deleted them,
  # also where nothing would roll that back.
  before_destroy :deletable_only, prepend: true

  # DSP-03: a crew's SOS first, then critical first, then the longest wait.
  scope :on_board, lambda {
    where(status: ACTIVE).in_order_of(:type, %w[ SosCall ], filter: false).order(priority: :desc, received_at: :asc)
  }

  def self.policy_class = CallPolicy

  # Where the call is: the name of its site, its words in a heading, the
  # district whose cars are offered first, and what a route leads to.
  def place = guarded_site.name

  def title = "#{summary} at #{place}"

  def district = guarded_site.district

  def destination = guarded_site.address

  # UPD-09: the outcomes offered at closing; Help given is for a crew's SOS.
  def outcome_choices = self.class.outcomes.keys - %w[ help_given ]

  def waiting_minutes(now = Time.current) = ((now - received_at) / 60).floor

  # 2.10: how long the client waited until the first car arrived.
  def response_minutes
    first = [ arrived_at, *backups.map(&:arrived_at) ].compact.min
    first && ((first - received_at) / 60).round(1)
  end

  # 2.10: how long the call took, or has taken so far while it is active.
  def handling_minutes(now = Time.current) = (((closed_at || now) - received_at) / 60).floor

  # DSP-03, DSP-05, CRW-06: where the car of an active call is: none yet; sent
  # and not accepted, unanswered once the reminders are over; accepted and on
  # the way; on site, unless its crew marked Arrived far from the site or its
  # phone gave no position (CRW-09).
  def arrival(now = Time.current)
    case status
    when "pending" then "waiting"
    when "dispatched" then dispatch_minutes(now) >= REMINDERS ? "unanswered" : "sent"
    when "accepted" then "on-the-way"
    when "on_scene" then on_site
    end
  end

  # CRW-07: where the phone of the crew of the call's own car was at Arrived;
  # none when the dispatcher recorded the arrival.
  def arrival_position = step_positions.find { |position| position.arrival? && position.backup_id.nil? }

  def dispatch_minutes(now = Time.current) = ((now - dispatched_at) / 60).floor

  def acceptance_minutes(now = Time.current) = ((now - accepted_at) / 60).floor

  # BR-23: kept while it was received within the period the administrator
  # set; days are those of Riga.
  def kept? = received_at.to_date >= Setting.current.calls_kept_from

  # The last day it is kept; from the next one it can be deleted. Months are
  # those of the calendar, so the day is found, not computed.
  def kept_until
    months = Setting.current.call_months
    day = received_at.to_date >> months
    day += 1 until (day << months) > received_at.to_date
    day - 1
  end

  private

  def at_site? = true

  # UPD-09: an outcome the enumeration knows, but not for this kind of call.
  def outcome_of_its_kind
    return if outcome.nil? || outcome_choices.include?(outcome) || !self.class.outcomes.key?(outcome)

    errors.add(:outcome, outcome_refusal)
  end

  def outcome_refusal = "is only for a crew's SOS"

  def on_site
    position = arrival_position
    if position&.far? then "far"
    elsif position&.known? == false then "no-position"
    else "on-site"
    end
  end

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

  # BR-8, BR-23: an active call is never deleted, and a finished one not
  # while it is kept; the first reason is the one told.
  def deletable_only
    reason = if status_in_database.in?(ACTIVE) then "Active call cannot be deleted; cancel or close it first"
    elsif kept? then "Call is kept until #{I18n.l(kept_until)} and cannot be deleted"
    end
    return unless reason

    errors.add(:base, reason)
    throw :abort
  end
end
