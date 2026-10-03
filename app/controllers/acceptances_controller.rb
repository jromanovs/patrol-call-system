# UPD-12, CRW-02: the crew has accepted the call, on its screen or by radio
# to the dispatcher; the reminders stop.
class AcceptancesController < CallStepsController
  skip_before_action :keep_crew_on_its_screen

  def create
    redirect_to home_path, notice: step.accept
  end

  private

  def permission = :accept?
end
