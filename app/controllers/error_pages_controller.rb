# BR-14: the list of the errors of production is the administrator's. The
# pages of solid_errors are built on this controller
# (config/initializers/solid_errors.rb).
class ErrorPagesController < ApplicationController
  before_action -> { authorize :error, :index? }
end
