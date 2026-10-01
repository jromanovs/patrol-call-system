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

  private

  def end_sessions
    sessions.destroy_all
  end
end
