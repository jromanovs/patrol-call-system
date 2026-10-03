# TRK-01, TRK-02: the cars' position sources and identifiers are the administrator's (BR-14).
class TrackingPolicy < ApplicationPolicy
  def show? = user&.administrator? || false
  alias update? show?
end
