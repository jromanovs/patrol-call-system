# UPD-08: the crew has arrived; the response time is shown.
class ArrivalsController < CallStepsController
  def create
    redirect_to root_path, notice: step.arrive
  end
end
