# CRW-01: the crew screen — the car of the signed-in crew and its active call.
class CrewsController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def show
    authorize :crew, :show?
    @car = Current.user.patrol_car
    @call = @car.calls.where(status: Call::ACTIVE).includes(:patrol_car, guarded_site: :address).first
    @map = MapBuild.new.current
    @marker = MapMarker.for([ @call.guarded_site ]).first if @call && @map
  end
end
