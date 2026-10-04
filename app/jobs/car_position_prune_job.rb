# TRK-05, BR-20: once a night the car positions older than the period the
# administrator set are deleted, whatever the cars' sources are by then.
class CarPositionPruneJob < ApplicationJob
  def perform = CarPosition.prune
end
