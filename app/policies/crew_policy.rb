# CRW-01: the crew screen is the crew's own.
class CrewPolicy < ApplicationPolicy
  def show? = user&.crew? || false
end
