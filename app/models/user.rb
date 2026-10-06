class User < ApplicationRecord
  include KindByContent

  # USR-07: the user's picture — a photo of theirs or their Gravatar.
  PICTURE_TYPES = %w[ image/jpeg image/png image/webp ].freeze
  PICTURE_LIMIT = 2.megabytes
  PICTURE_REFUSAL = "Picture must be a JPEG, PNG or WebP image of at most 2 MB".freeze

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
  # The same holds for the picture, which goes with a deleted user.
  has_one_attached :avatar
  has_many :push_subscriptions, through: :sessions

  enum :role, { dispatcher: 0, supervisor: 1, administrator: 2, crew: 3 }, validate: true
  # USR-09: how the pages look for the user. The prefix keeps the names of
  # the themes off the class, where `system` is Ruby's own.
  enum :theme, { system: 0, light: 1, dark: 2 }, prefix: true, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, length: { in: 2..100 }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :google_uid, uniqueness: true, allow_nil: true
  # A picture being attached is checked; one being taken away has nothing to
  # check.
  validate :picture_is_a_small_image, if: -> { attachment_changes["avatar"] && avatar.attached? }
  # 2.5: the car whose calls a crew works; no other role has one.
  validates :patrol_car, presence: { message: "must be chosen for a crew" }, if: :crew?
  validates :patrol_car, absence: { message: "is only for a crew" }, unless: :crew?

  before_update :void_api_key, if: -> { will_save_change_to_active?(to: false) || will_save_change_to_password_digest? }
  before_update :forget_google_account, if: :will_save_change_to_email_address?
  after_update_commit :end_sessions, if: -> { saved_change_to_active?(to: false) }
  # USR-06, USR-08: whoever knew the former password is signed out, also
  # when an administrator set the new one. In the transaction of the change:
  # both are kept or neither.
  after_update :end_other_sessions, if: :saved_change_to_password_digest?

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

  # USR-06: the user's own change of the password. The current one is asked
  # for, so that a session left open cannot take the account for good. The
  # current password and the repeat are strings, never nil, which would skip
  # their checks; a new password is the characters of whatever was sent, and
  # one of nothing is nil, which is refused as none, where an empty string
  # would be passed over and the old one kept.
  def change_password(current:, password:, confirmation:)
    assign_attributes(password_challenge: current.to_s, password: password.to_s.presence, password_confirmation: confirmation.to_s)
    save
  end

  # USR-08: a new password an administrator sets for the user, typed twice.
  # The repeat is a string, never nil, which would skip its check; a new
  # password of nothing is nil, which is refused as none.
  def set_password(password:, confirmation:)
    update(password: password.to_s.presence, password_confirmation: confirmation.to_s)
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

  def picture_is_a_small_image
    small = avatar.blob.byte_size <= PICTURE_LIMIT
    errors.add(:avatar, PICTURE_REFUSAL) unless small && kind_of(:avatar).in?(PICTURE_TYPES)
  end

  # BR-17: the calls the user registered, dispatched, acknowledged or sent a
  # further car to.
  def worked
    registered_calls.ids | dispatched_calls.ids | acknowledged_calls.ids | sent_backups.distinct.pluck(:call_id)
  end

  # BR-13: the API key is void in the same save. For a user made inactive,
  # also if made active again later; with a new password, since whoever knew
  # the former one may have issued the key.
  def void_api_key
    self.api_key_digest = nil
    self.api_key_issued_at = nil
  end

  # BR-15: the stored Google account is the one of the address Google
  # verified. With another address it would refuse the account of the new
  # one for good; that account is stored at its first sign-in instead.
  def forget_google_account
    self.google_uid = nil
  end

  def end_sessions
    sessions.destroy_all
  end

  # The session that saved the change stays when it is the user's own: the
  # one who just typed the new password is not sent to type it again.
  def end_other_sessions
    sessions.where.not(id: Current.session).destroy_all
  end
end
