# TRK-05: what the administrator sets for the whole system; one row.
class Setting < ApplicationRecord
  # BR-20: car positions are kept this many months at least and at most; the
  # upper end is only what a date can still count.
  MONTHS = 3..1200

  validate :months_within_reach

  # One row, by the index settings_one_row: a request that lost the race to
  # create it takes the winner's.
  def self.current
    first || create!
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  # BR-20: the period as a length of time.
  def kept = position_months.months

  def shorter?(months) = months.to_i < position_months_in_database

  private

  def months_within_reach
    months = position_months_before_type_cast
    whole = Integer(months.to_s, 10, exception: false)
    return errors.add(:base, "Keep positions for at least #{MONTHS.min} months") unless whole && whole >= MONTHS.min

    errors.add(:base, "Keep positions for at most #{MONTHS.max} months") if whole > MONTHS.max
  end
end
