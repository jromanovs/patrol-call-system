class Session < ApplicationRecord
  belongs_to :user
  # CRW-05: the notices on a phone end with the sign-in on it.
  has_many :push_subscriptions, dependent: :delete_all

  # BR-13: an inactive user is signed out of pages and of the live connection.
  scope :of_active_users, -> { joins(:user).merge(User.where(active: true)) }
end
