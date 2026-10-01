# UPD-10: cancelling a pending or dispatched call with an optional reason.
class CancellationsController < CallStepsController
  def new; end

  def create
    step.cancel(params[:reason])
    redirect_to root_path, notice: "Call cancelled"
  end
end
