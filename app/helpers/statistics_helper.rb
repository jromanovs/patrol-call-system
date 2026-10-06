module StatisticsHelper
  # CALC-02: an average in minutes with one decimal, or a dash without one.
  def average_minutes(value) = value ? t("common.minutes", count: decimal(value)) : "—"
end
