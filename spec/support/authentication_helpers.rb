# Signs a user in for request specs the way the Rails authentication
# generator does for its own tests: a session record and its signed cookie.
module AuthenticationHelpers
  def sign_in_as(user)
    Current.session = user.sessions.create!
    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
