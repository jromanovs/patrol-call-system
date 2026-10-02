module Api
  module V1
    # API-01, API-02: the calls, with the filters and order of the call list
    # (FLT-01 … FLT-03, SRT-01).
    class CallsController < BaseController
      def index
        authorize Call
        filter = CallFilter.new(params.permit(*::CallsController::FILTERS))
        return invalid(filter) if filter.invalid?

        @calls = filter.results.includes(:registered_by, :dispatched_by)
      end

      def show
        @call = authorize Call.includes(:guarded_site, :patrol_car, :registered_by, :dispatched_by).find(params.expect(:id))
      end
    end
  end
end
