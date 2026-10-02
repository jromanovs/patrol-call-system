class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_user

  # BR-13: a page knows the user by the browser session, an API request by
  # the user's API key.
  def user = session&.user || api_user
end
