# API-11, TRK-03, BR-20: the positions the Traccar Client app on a crew's
# phone sends. The app has no sign-in and is no browser, so this is no
# ApplicationController; the car is known by its identifier alone.
class TraccarController < ActionController::API
  # The requests of each identifier within the last minute, in this process.
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 30, within: 1.minute, by: -> { params[:id].to_s }, store: COUNTS
  # A JSON body is not logged a second time under the controller's name.
  wrap_parameters false

  # While tracking is off the phone is told 200 all the same, so that it
  # piles up no positions to send again.
  def create
    return head(:ok) unless Setting.current.car_tracking?

    car = PatrolCar.find_by_tracking_key(params[:id])
    return head(:not_found) unless car
    return head(:bad_request) unless car.car_positions.create(CarPosition.reported(params)).persisted?

    CarPosition.prune
    Turbo::StreamsChannel.broadcast_refresh_later_to(:board)
    head :ok
  end
end
