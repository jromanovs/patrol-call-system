# UPD-06, UPD-07, DYN-07: the dialog of free cars and the dispatch itself.
class DispatchesController < CallStepsController
  def new
    district = @call.guarded_site.district
    @cars = PatrolCar.available.in_order_of(:district, [ district ], filter: false).order(:call_sign)
  end

  def create
    car = PatrolCar.find(params.expect(:patrol_car_id))
    step.dispatch(car)
    redirect_to root_path, notice: "#{car.call_sign} dispatched to #{@call.guarded_site.name}"
  end
end
