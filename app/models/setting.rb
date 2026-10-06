# TRK-05: what the administrator sets for the whole system; one row.
class Setting < ApplicationRecord
  # BR-20, BR-23: a period runs this many months at least and at most; the
  # upper end is only what a date can still count.
  MONTHS = 3..1200
  # The columns that hold the months of a period.
  PERIODS = %i[ position_months call_months ].freeze

  # A refusal is whole as it stands and is shown beside its own field.
  validate :months_within_reach

  # One row, by the index settings_one_row: a request that lost the race to
  # create it takes the winner's. The attempt has a transaction of its own, so
  # that its refusal ends no transaction around it.
  def self.current
    first || transaction(requires_new: true) { create! }
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  # BR-20: the period as a length of time.
  def kept = position_months.months

  def shorter?(months) = months.to_i < position_months_in_database

  # BR-23: the first day whose calls are still kept; a call received before
  # it can be deleted.
  def calls_kept_from = Time.zone.today << call_months

  private

  def months_within_reach
    PERIODS.each do |column|
      whole = Integer(public_send(:"#{column}_before_type_cast").to_s, 10, exception: false)
      if whole.nil? || whole < MONTHS.min then errors.add(column, :below_least, months: MONTHS.min)
      elsif whole > MONTHS.max then errors.add(column, :above_most, months: MONTHS.max)
      end
    end
  end
end
