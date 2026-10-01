require "rails_helper"

RSpec.describe "Sign-in with Google" do
  let!(:user) { create(:user, email_address: "dispatcher@example.com") }

  before { OmniAuth.config.test_mode = true }
  after { OmniAuth.config.mock_auth[:google_oauth2] = nil }

  def google_returns(email:, uid: "google-123", verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: { email: email },
      extra: { raw_info: { email_verified: verified } }
    )
    post "/auth/google_oauth2"
    follow_redirect!
  end

  it "signs in an existing active user and remembers the Google account", :aggregate_failures do
    google_returns(email: "Dispatcher@Example.com")

    expect(response).to redirect_to(root_path)
    expect(user.reload.google_uid).to eq("google-123")
  end

  it "refuses an address that belongs to no user and creates nobody", :aggregate_failures do
    expect { google_returns(email: "stranger@example.com") }.not_to change(User, :count)

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("No account for this address. Ask the administrator.")
  end

  it "refuses an inactive user" do
    user.update!(active: false)
    google_returns(email: user.email_address)

    expect(flash[:alert]).to eq("No account for this address. Ask the administrator.")
  end

  it "refuses an address that Google has not verified" do
    google_returns(email: user.email_address, verified: false)

    expect(flash[:alert]).to eq("No account for this address. Ask the administrator.")
  end

  it "refuses a different Google account for a user already linked to one" do
    user.update!(google_uid: "google-999")
    google_returns(email: user.email_address)

    expect(flash[:alert]).to eq("No account for this address. Ask the administrator.")
  end
end
