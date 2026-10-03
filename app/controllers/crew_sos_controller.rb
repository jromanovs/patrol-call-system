# ADD-12, CRW-11: the crew asks for help from its screen. The question comes
# first; only its own button sends the signal.
class CrewSosController < ApplicationController
  # The signals of each user within the last minute, in this process.
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  skip_before_action :keep_crew_on_its_screen
  before_action { authorize :crew, :show? }
  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, store: COUNTS, only: :create,
             with: -> { redirect_to crew_path, alert: "Too many signals in a minute; the dispatcher has your SOS" }

  def new
    @car = Current.user.patrol_car
  end

  def create
    car = Current.user.patrol_car
    SosCall.signal(car, place_of(car), by: Current.user)
    redirect_to crew_path
  end

  private

  # Where the phone is; when it gives no position, the newest kept position
  # of the car with its time; or no place, as the signal goes all the same.
  def place_of(car)
    phone = CarPosition.from_phone(params)
    return phone if SosCall.on_earth?(phone)

    last = car.car_positions.where(recorded_at: CarPosition::KEPT.ago..).order(recorded_at: :desc).first
    last ? { **last.slice(:latitude, :longitude, :accuracy).symbolize_keys, placed_at: last.recorded_at } : {}
  end
end
