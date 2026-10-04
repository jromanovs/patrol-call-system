class User < ApplicationRecord
  has_secure_password
  belongs_to :patrol_car, optional: true
  # BR-17: a call keeps the users who worked on it.
  has_many :registered_calls, class_name: "Call", foreign_key: :registered_by_id, inverse_of: :registered_by,
                              dependent: :restrict_with_error
  has_many :dispatched_calls, class_name: "Call", foreign_key: :dispatched_by_id, inverse_of: :dispatched_by,
                              dependent: :restrict_with_error
  has_many :acknowledged_calls, class_name: "Call", foreign_key: :acknowledged_by_id, inverse_of: :acknowledged_by,
                                dependent: :restrict_with_error
  has_many :sent_backups, class_name: "Backup", foreign_key: :sent_by_id, inverse_of: :sent_by,
                          dependent: :restrict_with_error
  # BR-18, BR-19: the crew's positions and photos go only with their calls.
  has_many :step_positions, dependent: :restrict_with_error
  has_many :call_photos, dependent: :restrict_with_error
  # After the refusals above: these run in the order written, and a user who
  # stays keeps the sessions also where nothing would roll their deletion back.
  has_many :sessions, dependent: :destroy
  has_many :push_subscriptions, through: :sessions

  enum :role, { dispatcher: 0, supervisor: 1, administrator: 2, crew: 3 }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, length: { in: 2..100 }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :google_uid, uniqueness: true, allow_nil: true
  # 2.5: the car whose calls a crew works; no other role has one.
  validates :patrol_car, presence: { message: "must be chosen for a crew" }, if: :crew?
  validates :patrol_car, absence: { message: "is only for a crew" }, unless: :crew?

  before_update :void_api_key, if: -> { will_save_change_to_active?(to: false) }
  after_update_commit :end_sessions, if: -> { saved_change_to_active?(to: false) }

  # USR-04, BR-13: the active user the API key belongs to. The key is random
  # and long, so a plain digest is enough to find it and nothing to recover
  # it from.
  def self.find_by_api_key(key)
    where(active: true).find_by(api_key_digest: api_key_digest(key)) if key.present?
  end

  def self.api_key_digest(key) = Digest::SHA256.hexdigest(key)

  # A new key replaces the old one; only its digest is kept.
  def issue_api_key
    SecureRandom.base58(40).tap do |key|
      update!(api_key_digest: self.class.api_key_digest(key), api_key_issued_at: Time.current)
    end
  end

  # USR-03: why a user stays. A call counts once, whatever ties the user to it.
  def kept_reason
    recorded = step_positions.distinct.pluck(:call_id) | call_photos.distinct.pluck(:call_id)
    tied = worked
    kept = (tied | recorded).size
    held = tied.empty? ? "positions or photos kept at #{kept}" : kept
    "User has #{held} #{'call'.pluralize(kept)} and cannot be deleted; make the user inactive instead"
  end

  private

  # BR-17: the calls the user registered, dispatched, acknowledged or sent a
  # further car to.
  def worked
    registered_calls.ids | dispatched_calls.ids | acknowledged_calls.ids | sent_backups.distinct.pluck(:call_id)
  end

  # USR-02: the API key is void in the same save, also if the user is made
  # active again later.
  def void_api_key
    self.api_key_digest = nil
    self.api_key_issued_at = nil
  end

  def end_sessions
    sessions.destroy_all
  end
end
