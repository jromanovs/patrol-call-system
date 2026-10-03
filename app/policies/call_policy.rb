# The staff sees, registers and edits calls: the supervisor and the
# administrator can do all the dispatcher can (BR-14).
class CallPolicy < ApplicationPolicy
  %i[ index? show? create? update? ].each do |action|
    define_method(action) { staff? }
  end

  # CRW-02: the crew accepts its own car's call and records its arrival and
  # closing; the staff, of any call.
  def arrive? = staff? || own_car?
  alias accept? arrive?
  alias close? arrive?

  # DEL-05 … DEL-08: the supervisor and the administrator.
  def destroy? = staff? && (user.supervisor? || user.administrator?)

  private

  def own_car? = user&.crew? && record.patrol_car_id.present? && record.patrol_car_id == user.patrol_car_id
end
