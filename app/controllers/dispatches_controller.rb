# UPD-06, UPD-07, DYN-07: the dialog of free cars and the dispatch itself.
class DispatchesController < CallStepsController
  def new
    # BR-21: the car that asks for help is not sent to itself.
    @cars = PatrolCar.available.where.not(id: @call.raised_by_id)
                     .in_order_of(:district, [ @call.district ], filter: false).order(:call_sign)
  end

  def create
    car = PatrolCar.find(params.expect(:patrol_car_id))
    step.dispatch(car)
    redirect_to root_path, notice: "#{car.call_sign} dispatched to #{@call.place}"
  end
end
