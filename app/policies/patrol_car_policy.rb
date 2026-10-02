# The staff maintains cars: the dispatcher does, and the
# supervisor and the administrator can do all the dispatcher can (BR-14).
class PatrolCarPolicy < ApplicationPolicy
  %i[ index? show? create? update? destroy? ].each do |action|
    define_method(action) { staff? }
  end
end
