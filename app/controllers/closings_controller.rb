# UPD-09, CRW-02: closing a call with its outcome and an optional note.
class ClosingsController < CallStepsController
  skip_before_action :keep_crew_on_its_screen

  def new; end

  def create
    step.close(params[:outcome], params[:note], position: crew_position)
    redirect_to home_path, notice: "Call closed"
  end

  private

  def permission = :close?
end
