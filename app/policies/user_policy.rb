# Users are managed by the administrator only (BR-14).
class UserPolicy < ApplicationPolicy
  %i[ index? show? create? update? destroy? ].each do |action|
    define_method(action) { user&.administrator? || false }
  end
end
