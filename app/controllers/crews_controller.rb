# CRW-01: the crew screen — the car of the signed-in crew and its active call.
class CrewsController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def show
    authorize :crew, :show?
    @car = Current.user.patrol_car
    @call = @car.calls.where(status: Call::ACTIVE).includes(:patrol_car, :step_positions, guarded_site: :address).first
    @map = MapBuild.new.current
    @notice_key = CrewNotice.keys&.fetch(:public_key)
    # Its own call only, even when another car serves the same site.
    @marker = MapMarker.new(site: @call.guarded_site, call: @call) if @call && @map
  end
end
