# TRK-05, DEL-09: the settings of the system are the administrator's (BR-14).
class SettingPolicy < ApplicationPolicy
  def show? = update?

  def update? = user&.administrator? || false
end
