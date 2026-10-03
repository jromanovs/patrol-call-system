# The settings of the system, one row: whether the cars are tracked (TRK-01).
class Setting < ApplicationRecord
  def self.current = first || create!
end
