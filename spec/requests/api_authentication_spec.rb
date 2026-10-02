require "rails_helper"

RSpec.describe "API sign-in by key (BR-13, USR-04)" do
  let(:user) { create(:user) }
  let(:message) { { "error" => "Send the API key of an active user: Authorization: Bearer <key>" } }

  def answer(headers = {})
    get api_v1_sites_path, headers: headers
    [ response.status, response.parsed_body ]
  end

  it "answers 401 without a key, with a wrong key and with an inactive user's key", :aggregate_failures do
    expect(answer).to eq([ 401, message ])
    expect(answer("Authorization" => "Bearer wrong")).to eq([ 401, message ])
    key = user.issue_api_key
    user.update!(active: false)
    expect(answer("Authorization" => "Bearer #{key}")).to eq([ 401, message ])
    expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
  end

  it "refuses the key of a user made inactive without the usual callbacks (BR-13)" do
    key = user.issue_api_key
    user.update_column(:active, false)

    expect(answer("Authorization" => "Bearer #{key}").first).to eq(401)
  end

  it "does not take the browser session in place of a key" do
    sign_in_as(user)

    expect(answer.first).to eq(401)
  end

  it "lets the holder of a valid key in" do
    expect(answer("Authorization" => "Bearer #{user.issue_api_key}").first).to eq(200)
  end

  it "refuses the old key once a new one is issued (USR-04)", :aggregate_failures do
    old_key = user.issue_api_key
    new_key = user.issue_api_key

    expect(answer("Authorization" => "Bearer #{old_key}").first).to eq(401)
    expect(answer("Authorization" => "Bearer #{new_key}").first).to eq(200)
  end
end
