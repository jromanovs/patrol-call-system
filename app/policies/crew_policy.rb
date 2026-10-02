# CRW-01: the crew screen is the crew's own.
class CrewPolicy < ApplicationPolicy
  def show? = user&.crew? || false

  # CRW-04, BR-14: only a crew user turns notices on.
  alias notices? show?
end
