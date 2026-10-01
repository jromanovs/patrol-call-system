# CALC-01 … CALC-04 over the calls of the call list filter (FLT-01); a filter
# without a period gives the current month in Riga time.
class StatisticsController < ApplicationController
  FILTERS = CallsController::FILTERS - %i[ sort direction ]

  def show
    authorize :statistics
    @criteria = criteria
    @filter = CallFilter.new(@criteria)
    @filter.validate
    @statistics = CallStatistics.new(@filter.selected, top: params[:top])
    @statistics.validate
  end

  private

  def criteria
    given = params.permit(*FILTERS).to_h.compact_blank
    return given if given.key?("from") || given.key?("to")

    month = Time.zone.today.all_month
    given.merge("from" => month.first.iso8601, "to" => month.last.iso8601)
  end
end
