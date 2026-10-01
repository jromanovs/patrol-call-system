require "rails_helper"

RSpec.describe "Sessions" do
  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, password: password) }

  it "sends a visitor who is not signed in to the sign-in page" do
    get "/calls"

    expect(response).to redirect_to(new_session_path)
  end

  it "signs a user in with the right password and opens the board", :aggregate_failures do
    post session_path, params: { email_address: user.email_address, password: password }
    expect(response).to redirect_to(root_path)

    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "refuses a wrong password with a message that does not say which part was wrong", :aggregate_failures do
    post session_path, params: { email_address: user.email_address, password: "wrong-password" }

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("Try another email address or password.")
  end

  it "signs the user out", :aggregate_failures do
    sign_in_as(user)
    delete session_path
    expect(response).to redirect_to(new_session_path)

    get root_path
    expect(response).to redirect_to(new_session_path)
  end
end
