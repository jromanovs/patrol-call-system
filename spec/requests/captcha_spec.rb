require "rails_helper"

RSpec.describe "Captcha challenge" do
  it "hands out a signed PBKDF2 challenge to a visitor who is not signed in", :aggregate_failures do
    get captcha_challenge_path

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.dig("parameters", "algorithm")).to eq("PBKDF2/SHA-256")
    expect(body["signature"]).to be_present
  end
end
