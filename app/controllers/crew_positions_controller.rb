# TRK-04, BR-20: the position the crew screen sends for the crew's own car,
# kept only while the car's source is the crew's phone.
class CrewPositionsController < ApplicationController
  # The positions of each user within the last minute, in this process.
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  skip_before_action :keep_crew_on_its_screen
  rate_limit to: 10, within: 1.minute, by: -> { Current.user&.id }, store: COUNTS

  # 409 tells the screen that the source has changed and it is to stop.
  def create
    authorize :crew, :show?
    car = Current.user.patrol_car
    return head(:conflict) unless car.crew_phone?

    position = car.car_positions.create(source: :crew_phone, **CarPosition.from_phone(params))
    return head(:unprocessable_content) unless position.persisted?

    Turbo::StreamsChannel.broadcast_refresh_later_to(:cars)
    head :no_content
  end
end
