class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { dispatcher: 0, supervisor: 1, administrator: 2 }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, length: { in: 2..100 }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :google_uid, uniqueness: true, allow_nil: true

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

  private

  def end_sessions
    sessions.destroy_all
  end
end
