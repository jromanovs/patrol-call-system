# Every signed-in user registers and edits calls: the supervisor and the
# administrator can do all the dispatcher can (BR-14).
class CallPolicy < ApplicationPolicy
  def create? = user.present?

  def update? = user.present?
end
