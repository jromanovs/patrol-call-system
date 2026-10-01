# Every signed-in user sees the statistics (BR-14).
class StatisticsPolicy < ApplicationPolicy
  def show? = user.present?
end
