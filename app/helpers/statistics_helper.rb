module StatisticsHelper
  # CALC-02: an average in minutes with one decimal, or a dash without one.
  def average_minutes(value) = value ? "#{value} min" : "—"
end
