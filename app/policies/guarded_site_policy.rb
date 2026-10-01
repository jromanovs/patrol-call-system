# Every signed-in user maintains sites: the dispatcher does, and the
# supervisor and the administrator can do all the dispatcher can (BR-14).
class GuardedSitePolicy < ApplicationPolicy
  %i[ index? show? create? update? destroy? ].each do |action|
    define_method(action) { user.present? }
  end
end
