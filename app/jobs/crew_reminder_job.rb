# CRW-06: a reminder of a call its crew has not accepted, one a minute after
# the dispatch, at most Call::REMINDERS; each is a notice of its own, so that
# the phone sounds again. After the last, every open screen shows the call
# unanswered.
class CrewReminderJob < ApplicationJob
  queue_as :default
  # A call deleted before its reminder went needs none.
  discard_on ActiveJob::DeserializationError

  def perform(call, number)
    return unless call.dispatched?

    # Planned first, so that a failing push service stops no later reminder.
    if number < Call::REMINDERS
      self.class.set(wait: 1.minute).perform_later(call, number + 1)
    else
      Turbo::StreamsChannel.broadcast_refresh_later_to(:board)
    end
    CrewNotice.new(call, reminder: number).deliver
  end
end
