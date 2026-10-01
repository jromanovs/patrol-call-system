class Session < ApplicationRecord
  belongs_to :user

  # BR-13: an inactive user is signed out of pages and of the live connection.
  scope :of_active_users, -> { joins(:user).merge(User.where(active: true)) }
end
