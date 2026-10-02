module Api
  module V1
    # API-07: CALC-01 … CALC-04 over the calls of the call list filter, the
    # current month in Riga time without a period; null where the page shows
    # a dash.
    class StatisticsController < BaseController
      def show
        authorize :statistics
        criteria = params.permit(*::StatisticsController::FILTERS).to_h.compact_blank
        @filter = CallFilter.new(CallStatistics.with_period(criteria))
        @statistics = CallStatistics.new(@filter.selected, top: params[:top])
        messages = [ @filter, @statistics ].reject(&:valid?).flat_map { |record| record.errors.full_messages }
        render json: { errors: { base: messages } }, status: :unprocessable_content if messages.any?
      end
    end
  end
end
