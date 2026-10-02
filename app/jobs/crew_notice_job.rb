# CRW-04: the notice of a new call, sent after the dispatch is saved, so that
# a slow push service never holds up the dispatcher.
class CrewNoticeJob < ApplicationJob
  queue_as :default
  # A call deleted before its notice went needs none.
  discard_on ActiveJob::DeserializationError

  def perform(call) = CrewNotice.new(call).deliver
end
