# API-11: what the Traccar Client app sends, written to the log as it came,
# so that the receiver of car positions is built on it. The app has no sign-in
# and is no browser, so this is no ApplicationController; it is told 200, and
# nothing is kept.
class TraccarController < ActionController::API
  # The requests of each address within the last minute, in this process.
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 30, within: 1.minute, store: COUNTS

  def create
    Rails.logger.info("Traccar Client: #{request.method} ?#{request.query_string} #{request.media_type} " \
                      "#{request.raw_post.to_s.first(2000)} (#{request.user_agent})")
    head :ok
  end
end
