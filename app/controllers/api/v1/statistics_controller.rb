module Api
  module V1
    # API-07: CALC-01 … CALC-04 over the calls of the call list filter, the
    # current month in Riga time without a period; null where the page shows
    # a dash.
    class StatisticsController < BaseController
      def show
        authorize :statistics
        @criteria = CallStatistics.with_period(params.permit(*::StatisticsController::FILTERS).to_h.compact_blank)
        filter = CallFilter.new(@criteria)
        return invalid(filter) if filter.invalid?

        @statistics = CallStatistics.new(filter.selected, top: params[:top])
        invalid(@statistics) if @statistics.invalid?
      end
    end
  end
end
