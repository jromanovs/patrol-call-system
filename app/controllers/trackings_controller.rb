# TRK-01, TRK-02: the administrator's page of car tracking — each car's
# position source and its identifier for Traccar Client.
class TrackingsController < ApplicationController
  before_action -> { authorize :tracking, action_name == "show" ? :show? : :update? }
  before_action :set_car, except: :show

  def show
    load_page
  end

  # The open main screens show or hide the car at once, and its crew screen
  # starts or stops sending positions.
  def choose_source
    return redirect_to(tracking_path, alert: "Choose a position source", status: :see_other) unless source

    @car.update!(position_source: source)
    Turbo::StreamsChannel.broadcast_refresh_later_to(:board)
    redirect_to tracking_path, notice: @car.tracked_words, status: :see_other
  end

  # A new identifier is shown on this one page; no cache keeps it, the
  # browser's included.
  def issue_key
    @key = @car.issue_tracking_key
    no_store
    load_page
    render :show, status: :created
  end

  private

  def set_car
    @car = PatrolCar.find(params.expect(:patrol_car_id))
  end

  def source = params[:position_source].presence_in(PatrolCar.position_sources.keys)

  def load_page
    @cars = PatrolCar.order(:call_sign)
    @positions = CarPosition.latest.index_by(&:patrol_car_id)
  end
end
