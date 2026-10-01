# UPD-09: closing a call with its outcome and an optional note.
class ClosingsController < CallStepsController
  def new; end

  def create
    step.close(params[:outcome], params[:note])
    redirect_to root_path, notice: "Call closed"
  end
end
