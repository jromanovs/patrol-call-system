# TRK-01, TRK-02: car tracking is the administrator's (BR-14).
class TrackingPolicy < ApplicationPolicy
  def show? = user&.administrator? || false
  alias update? show?
end
