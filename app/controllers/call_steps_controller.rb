# The common part of the steps of a call (2.10): the call, the rights, and the
# answer on the board. A refused step returns to the board with its message.
class CallStepsController < ApplicationController
  before_action :set_call

  rescue_from CallStep::Refused do |refusal|
    redirect_to root_path, alert: refusal.message
  end

  private

  def set_call
    @call = authorize Call.find(params.expect(:call_id)), :update?
  end

  def step = CallStep.new(@call, Current.user)
end
