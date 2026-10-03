# TRK-01, TRK-02: the administrator's page of car tracking — the switch, and
# the cars with their identifiers for Traccar Client.
class TrackingsController < ApplicationController
  before_action -> { authorize :tracking, action_name == "show" ? :show? : :update? }

  def show
    load_page
  end

  # The open main screens show or hide the cars at once.
  def update
    on = params[:car_tracking] == "1"
    Setting.current.update!(car_tracking: on)
    Turbo::StreamsChannel.broadcast_refresh_later_to(:cars)
    redirect_to tracking_path, notice: "Car tracking is #{on ? 'on' : 'off'}", status: :see_other
  end

  # A new identifier is shown on this one page; no cache keeps it, the
  # browser's included.
  def issue_key
    @car = PatrolCar.find(params.expect(:patrol_car_id))
    @key = @car.issue_tracking_key
    no_store
    load_page
    render :show, status: :created
  end

  private

  def load_page
    @setting = Setting.current
    @cars = PatrolCar.order(:call_sign)
    @positions = CarPosition.latest.index_by(&:patrol_car_id)
  end
end
