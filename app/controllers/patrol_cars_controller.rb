# Patrol cars (2.3): the list with search, filters and sorting, the car page,
# adding, editing, putting out of service and deleting.
class PatrolCarsController < ApplicationController
  FIELDS = %i[ call_sign plate_number model crew_size district status ].freeze

  before_action :set_car, only: %i[ show edit update destroy ]

  def index
    authorize PatrolCar
    @text = params[:q].to_s
    @cars = PatrolCar.list(text: @text, filters: params.permit(:status, :district),
                           sort: params[:sort], direction: params[:direction])
  end

  def show
    @current_call = @car.active_call
    # BR-21: the calls the car served, and those its crew raised by an SOS.
    @calls = Call.where(patrol_car: @car).or(Call.where(raised_by: @car))
                 .includes(:guarded_site, :raised_by).order(received_at: :desc).limit(10)
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
      redirect_to @car, status: :see_other, alert: @car.kept_reason
    end
  end

  private

  def default_sort = "call_sign"
  helper_method :default_sort

  def set_car
    @car = authorize PatrolCar.find(params.expect(:id))
  end

  def car_params = PatrolCar.by_hand(params.expect(patrol_car: FIELDS), @car)
end
