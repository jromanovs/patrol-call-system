# BR-14: the errors of production are the administrator's to read and resolve.
class ErrorPolicy < ApplicationPolicy
  def index? = user&.administrator? || false
end
