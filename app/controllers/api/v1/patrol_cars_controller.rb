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
    end
  end
end
