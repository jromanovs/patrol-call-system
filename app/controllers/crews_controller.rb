# CRW-01: the crew screen — the car of the signed-in crew and its active call.
class CrewsController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def show
    authorize :crew, :show?
    @car = Current.user.patrol_car
    @call = @car.calls.where(status: Call::ACTIVE)
                .includes(:patrol_car, :step_positions, :raised_by, guarded_site: :address).first
    @map = MapBuild.new.current
    @notice_key = CrewNotice.keys&.fetch(:public_key)
    # Its own call only, even when another car serves the same site; for a
    # crew's SOS, the place of the signal (BR-21).
    @marker = MapMarker.new(site: @call.guarded_site, call: @call) if @call&.destination && @map
    # CRW-11: the SOS this car raised, while it is active.
    @sos = SosCall.where(raised_by: @car, status: Call::ACTIVE).includes(:patrol_car).first
  end
end
