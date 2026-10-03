# CRW-04: the notice of a new call, sent after the dispatch is saved, so that
# a slow push service never holds up the dispatcher.
class CrewNoticeJob < ApplicationJob
  queue_as :default
  # A call deleted before its notice went needs none.
  discard_on ActiveJob::DeserializationError

  # With a car, the notice is for the crew of that further car (BR-22).
  def perform(call, car = nil) = (car ? CrewNotice.new(call, car:) : CrewNotice.new(call)).deliver
end
