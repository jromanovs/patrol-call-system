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

  # CRW-10, BR-19: the crew of the call's car adds photos while on site; the
  # staff sees them, that crew while the call is active.
  def add_photo? = own_car? && record.on_scene?
  def see_photos? = staff? || (own_car? && record.status.in?(Call::ACTIVE))

  # CRW-12: the crew of a further car of the call accepts it and marks its
  # own arrival; the staff, of any further car.
  def back? = staff? || (user&.crew? && record.backups.active.exists?(patrol_car_id: user.patrol_car_id))

  # DEL-05 … DEL-08: the supervisor and the administrator.
  def destroy? = staff? && (user.supervisor? || user.administrator?)

  private

  def own_car? = user&.crew? && record.patrol_car_id.present? && record.patrol_car_id == user.patrol_car_id
end
