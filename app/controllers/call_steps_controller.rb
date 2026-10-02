# The common part of the steps of a call (2.10): the call, the rights, and the
# answer on the board, or on the crew screen for the crew (CRW-02). A refused
# step returns there with its message.
class CallStepsController < ApplicationController
  before_action :set_call

  rescue_from CallStep::Refused do |refusal|
    redirect_to home_path, alert: refusal.message
  end

  private

  # The right a step asks for; the crew is granted only its own arrival and
  # closing (CRW-03).
  def permission = :update?

  def set_call
    @call = authorize Call.find(params.expect(:call_id)), permission
  end

  def step = CallStep.new(@call, Current.user)
end
