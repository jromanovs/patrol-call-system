# Patrol cars (2.3): the list with search, filters and sorting, the car page,
# adding, editing, putting out of service and deleting.
class PatrolCarsController < ApplicationController
  before_action :set_car, only: %i[ show edit update destroy ]

  def index
    authorize PatrolCar
    @text = params[:q].to_s
    @cars = PatrolCar.list(text: @text, filters: params.permit(:status, :district),
                           sort: params[:sort], direction: params[:direction])
  end

  def show
    @current_call = @car.active_call
    @calls = @car.calls.includes(:guarded_site).order(received_at: :desc).limit(10)
  end

  def new
    @car = authorize PatrolCar.new
  end

  def edit; end

  def create
    @car = authorize PatrolCar.new(car_params)
    if @car.save
      redirect_to @car, notice: "Car created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @car.update(car_params)
      redirect_to @car, notice: "Car updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DEL-03, DEL-04: a car with calls stays (BR-9).
  def destroy
    if @car.destroy
      redirect_to patrol_cars_path, notice: "Car deleted", status: :see_other
    else
      redirect_to @car, status: :see_other,
                        alert: "Car has #{helpers.pluralize(@car.calls.count, 'call')} and cannot be deleted; " \
                               "put it out of service instead"
    end
  end

  private

  def default_sort = "call_sign"
  helper_method :default_sort

  def set_car
    @car = authorize PatrolCar.find(params.expect(:id))
  end

  # BR-5: the status changes by hand only between available and out of
  # service, and not while a call holds the car.
  def car_params
    fields = params.expect(patrol_car: %i[ call_sign plate_number model crew_size district status ])
    by_hand = PatrolCar::SET_BY_HAND.include?(fields[:status]) && (@car.nil? || @car.status.in?(PatrolCar::SET_BY_HAND))
    by_hand ? fields : fields.except(:status)
  end
end
