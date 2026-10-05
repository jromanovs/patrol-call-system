# TRK-01, TRK-02: the cars' position sources and identifiers are the
# administrator's (BR-14). How long positions are kept is a setting.
class TrackingPolicy < ApplicationPolicy
  def show? = user&.administrator? || false
  alias update? show?
end
