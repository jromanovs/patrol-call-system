# UPD-08, CRW-02: the crew has arrived; the response time is shown.
class ArrivalsController < CallStepsController
  skip_before_action :keep_crew_on_its_screen

  def create
    redirect_to home_path, notice: step.arrive(position: crew_position)
  end

  private

  def permission = :arrive?
end
