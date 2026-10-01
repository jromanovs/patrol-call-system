require "rails_helper"

RSpec.describe "Session cookie" do
  # Production protects forms with a CSRF token kept in the session, so every
  # page sets the session cookie; the test environment switches that off.
  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "keeps the next page working when the browser sends the session cookie back", :aggregate_failures do
    get "/"
    expect(response.cookies).to include("_patrol_call_system_session")

    get "/calls"
    expect(response).to have_http_status(:ok)
  end
end
