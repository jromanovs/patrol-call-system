# The main screen, the home page (DSP-03): the active-calls board and the
# cars over the map of every site under an active contract (DSP-05).
class BoardController < ApplicationController
  def index
    @calls = Call.on_board.includes(:patrol_car, :step_positions, guarded_site: :address).to_a
    @cars = PatrolCar.on_panel.to_a
    # TRK-03, BR-20: the cars' newest positions, while tracking is on.
    @positions = Setting.current.car_tracking? ? CarPosition.latest.index_by(&:patrol_car_id) : {}
    build = MapBuild.new
    @map = build.current
    return start_first_build(build) if @map.nil?

    @markers = MapMarker.for(GuardedSite.active.includes(:address).order(:name, :id))
    @focus = @markers.find { |marker| marker.site.id.to_s == params[:site] }
  end

  private

  # STO-06: at most once an hour, so visits never repeat a failed download.
  def start_first_build(build)
    MapBuildJob.perform_later unless build.attempted_since?(1.hour.ago)
  end
end
