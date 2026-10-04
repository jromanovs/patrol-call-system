# DEL-09: how long records are kept is the administrator's (BR-14).
class SettingPolicy < ApplicationPolicy
  def update? = user&.administrator? || false
end
