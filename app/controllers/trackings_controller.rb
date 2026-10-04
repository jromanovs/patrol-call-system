# TRK-01, TRK-02, TRK-05: the administrator's page of car tracking — each
# car's position source, its identifier for Traccar Client, and for how long
# positions are kept.
class TrackingsController < ApplicationController
  before_action -> { authorize :tracking, action_name == "show" ? :show? : :update? }
  before_action :set_car, only: %i[ choose_source issue_key ]

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

  # TRK-05: a shorter period deletes what a longer one kept, so it is saved
  # only after the question about it is answered.
  def keep_positions
    @setting = Setting.current
    @setting.position_months = params[:months]
    return refuse_period unless @setting.valid?
    return ask_about_shorter if @setting.shorter?(params[:months]) && params[:shorter] != "yes"

    @setting.save!
    redirect_to tracking_path, notice: "Car positions are kept for #{@setting.position_months} months", status: :see_other
  end

  private

  def refuse_period
    load_page
    render :show, status: :unprocessable_content
  end

  # On the open page the question goes into the dialog frame. Asked for as a
  # page, it is the dialog alone, as the other dialogs are.
  def ask_about_shorter
    @oldest = CarPosition.kept_since
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("modal", template: "trackings/shorter") }
      format.html { render :shorter, status: :unprocessable_content }
    end
  end

  def set_car
    @car = PatrolCar.find(params.expect(:patrol_car_id))
  end

  def source = params[:position_source].presence_in(PatrolCar.position_sources.keys)

  def load_page
    @cars = PatrolCar.order(:call_sign)
    # Of any age that is kept: this page tells what the system holds, not
    # what the map shows.
    @positions = CarPosition.latest(since: nil).index_by(&:patrol_car_id)
    @setting ||= Setting.current
    @oldest = CarPosition.kept_since
  end
end
