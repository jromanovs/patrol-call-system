# The staff sees the statistics (BR-14).
class StatisticsPolicy < ApplicationPolicy
  def show? = staff?
end
