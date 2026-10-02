module Api
  module V1
    # API-01, API-02: the patrol cars, with the search, filters and order of
    # the car list (FLT-06, SRT-03).
    class PatrolCarsController < BaseController
      def index
        authorize PatrolCar
        @cars = PatrolCar.list(text: params[:q].to_s, filters: params.permit(:status, :district),
                               sort: params[:sort], direction: params[:direction])
      end

      def show
        @car = authorize PatrolCar.find(params.expect(:id))
      end

      # API-03
      def create
        @car = authorize PatrolCar.new(fields)
        @car.save ? render(:show, status: :created) : invalid(@car)
      end

      # API-04: the status changes by hand only as on the car form (BR-5).
      def update
        @car = authorize PatrolCar.find(params.expect(:id))
        @car.update(fields(@car)) ? render(:show) : invalid(@car)
      end

      # API-05: a car with calls stays (BR-9).
      def destroy
        car = authorize PatrolCar.find(params.expect(:id))
        car.destroy ? head(:no_content) : refuse(car.kept_reason)
      end

      private

      def fields(car = nil) = PatrolCar.by_hand(params.permit(*::PatrolCarsController::FIELDS), car)
    end
  end
end
