# Every signed-in user sees, registers and edits calls: the supervisor and the
# administrator can do all the dispatcher can (BR-14).
class CallPolicy < ApplicationPolicy
  %i[ index? show? create? update? ].each do |action|
    define_method(action) { user.present? }
  end

  # DEL-05 … DEL-08: the supervisor and the administrator.
  def destroy? = user.present? && (user.supervisor? || user.administrator?)
end
