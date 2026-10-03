# TRK-01, TRK-02: the administrator's page of car tracking — each car's
# position source and its identifier for Traccar Client.
class TrackingsController < ApplicationController
  before_action -> { authorize :tracking, action_name == "show" ? :show? : :update? }
  before_action :set_car, except: :show

  # An identifier just issued is shown on this one page; no cache keeps it,
  # the browser's included.
  def show
    @issued = flash[:tracking_key]
    no_store if @issued
    load_page
  end

  # The car's own save refreshes the open screens: the main screens show or
  # hide the car at once, and its crew screen starts or stops sending.
  def choose_source
    return redirect_to(tracking_path, alert: "Choose a position source", status: :see_other) unless source

    @car.update!(position_source: source)
    redirect_to tracking_path, notice: @car.tracked_words, status: :see_other
  end

  # The new identifier travels to the page in the flash of the encrypted
  # session, for one request only, so that a reload of that page sends no
  # form again and issues nothing.
  def issue_key
    unless @car.traccar?
      return redirect_to(tracking_path, alert: "#{@car.call_sign} is not tracked by Traccar Client", status: :see_other)
    end

    flash[:tracking_key] = { "car" => @car.call_sign, "key" => @car.issue_tracking_key }
    redirect_to tracking_path, status: :see_other
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
