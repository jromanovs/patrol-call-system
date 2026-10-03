# API-11, TRK-03, BR-20: the positions the Traccar Client app on a crew's
# phone sends. The app has no sign-in and is no browser, so this is no
# ApplicationController; the car is known by its identifier alone.
class TraccarController < ActionController::API
  # The requests of each identifier within the last minute, in this process.
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 30, within: 1.minute, by: -> { params[:id].to_s }, store: COUNTS, unless: :sos?
  # ADD-11: a crew that asks for help is not held up by the positions its
  # phone has piled up; its signals have a count of their own.
  rate_limit to: 10, within: 1.minute, by: -> { params[:id].to_s }, store: COUNTS, name: "sos", if: :sos?
  # A JSON body is not logged a second time under the controller's name.
  wrap_parameters false

  # For a car whose source is not Traccar Client, and for a position that
  # sending again cannot mend, the phone is told 200 all the same, so that it
  # piles up nothing to send.
  def create
    car = PatrolCar.find_by_tracking_key(params[:id]) if params[:id].is_a?(String)
    return head(:not_found) unless car

    # ADD-11, BR-21: an SOS is taken whatever the car's position source.
    SosCall.signal(car, CarPosition.reported(params)) if sos?
    return head(:ok) unless car.traccar?
    return head(:ok) unless car.car_positions.create(source: :traccar, **CarPosition.reported(params)).persisted?

    CarPosition.prune
    # Only the main screens hear the cars move (TRK-03).
    Turbo::StreamsChannel.broadcast_refresh_later_to(:cars)
    head :ok
  end

  private

  def sos? = params[:alarm] == "sos"
end
