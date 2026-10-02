# CALC-01 … CALC-04 over the calls of the call list filter (FLT-01); a filter
# without a period gives the current month in Riga time.
class StatisticsController < ApplicationController
  FILTERS = CallsController::FILTERS - %i[ sort direction ]

  def show
    authorize :statistics
    @criteria = CallStatistics.with_period(params.permit(*FILTERS).to_h.compact_blank)
    @filter = CallFilter.new(@criteria)
    @filter.validate
    @statistics = CallStatistics.new(@filter.selected, top: params[:top])
    @statistics.validate
  end
end
