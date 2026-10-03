# API-11: what the Traccar Client app sends, written to the log as it came,
# so that the receiver of car positions is built on it. The app has no sign-in
# and is no browser, so this is no ApplicationController; it is told 200, and
# nothing is kept.
class TraccarController < ActionController::API
  BODY = 2000
  AGENT = 200
  # The requests of each address within the last minute, in this process.
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 30, within: 1.minute, store: COUNTS
  # A JSON body is not logged a second time under the controller's name.
  wrap_parameters false

  # Each part is written as an escaped string, so that a line break or a
  # control character in it stays visible and cannot start a line of its own.
  def create
    Rails.logger.info("Traccar Client: #{request.method} #{request.query_string.inspect} #{request.media_type.inspect} " \
                      "#{received_body.inspect} #{request.user_agent.to_s.byteslice(0, AGENT).inspect}")
    head :ok
  end

  private

  # Only the first bytes are read here, however large the body; a GET has
  # none. A form or JSON body Rails itself reads whole before this, to log
  # its parameters.
  def received_body
    stream = request.body
    return "" unless stream

    stream.rewind
    stream.read(BODY).to_s
  end
end
