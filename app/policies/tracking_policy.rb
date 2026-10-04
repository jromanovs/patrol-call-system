# TRK-01, TRK-02, TRK-05: the cars' position sources and identifiers, and how
# long positions are kept, are the administrator's (BR-14).
class TrackingPolicy < ApplicationPolicy
  def show? = user&.administrator? || false
  alias update? show?
end
