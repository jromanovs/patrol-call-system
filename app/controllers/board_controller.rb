# The main screen, the home page (DSP-03): the active-calls board and the
# cars over the map of every site under an active contract (DSP-05).
class BoardController < ApplicationController
  def index
    @calls = Call.on_board.includes(:patrol_car, :step_positions, :raised_by, :acknowledged_by, guarded_site: :address).to_a
    list_cars
    build = MapBuild.new
    @map = build.current
    return start_first_build(build) if @map.nil?

    mark_map
  end

  private

  # BR-21: the cars that ask for help come first on the panel. TRK-03,
  # BR-20: the newest position of each tracked car.
  def list_cars
    @asking = @calls.grep(SosCall).index_by(&:raised_by_id)
    @cars = PatrolCar.on_panel.to_a.partition { |car| @asking.key?(car.id) }.flatten
    @positions = CarPosition.latest.where(patrol_car: @cars.select(&:tracked?)).index_by(&:patrol_car_id)
  end

  # DSP-05: every site under an active contract and every crew's SOS; the
  # one asked for opens the map.
  def mark_map
    @markers = MapMarker.for(GuardedSite.active.includes(:address).order(:name, :id))
    @sos = MapMarker.sos(@calls)
    @focus = @markers.find { |marker| marker.site.id.to_s == params[:site] } ||
             @sos.find { |marker| marker.call.id.to_s == params[:sos] }
  end

  # STO-06: at most once an hour, so visits never repeat a failed download.
  def start_first_build(build)
    MapBuildJob.perform_later unless build.attempted_since?(1.hour.ago)
  end
end
