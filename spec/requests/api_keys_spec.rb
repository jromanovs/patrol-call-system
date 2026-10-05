require "rails_helper"

RSpec.describe "API key page" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "is opened from the header and says when no key is in force (USR-04)", :aggregate_failures do
    get root_path
    expect(response.parsed_body.at_css("header #account-menu a[href='#{api_key_path}']").text.strip).to eq("API key")

    get api_key_path
    expect(response.parsed_body.at_css("main").text).to include("No valid key")
  end

  it "says when a key stops working, before one is issued and after (USR-04, BR-13)", :aggregate_failures do
    rule = "A key stops working at once when a new one is issued, when your password changes, " \
           "and when your account is made inactive."

    get api_key_path
    expect(response.parsed_body.css("main p.note").map { |note| note.text.squish }).to include(rule)
    post api_key_path
    expect(response.parsed_body.css("main p.note").map { |note| note.text.squish }).to include(rule)
  end

  it "shows a new key once, then only when it was issued (USR-04)", :aggregate_failures do
    travel_to(Time.zone.local(2026, 10, 2, 10, 0)) { post api_key_path }

    key = response.parsed_body.at_css("#api-key").text.strip
    expect(User.find_by_api_key(key)).to eq(user)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body.at_css("meta[name='turbo-cache-control']")["content"]).to eq("no-cache")

    get api_key_path
    expect(response.body).not_to include(key)
    expect(response.parsed_body.at_css("main").text).to include("Issued 02.10.2026 10:00")
  end

  it "issues the key without Turbo, so the page with the key is shown at once" do
    get api_key_path

    expect(response.parsed_body.at_css("form[action='#{api_key_path}']")["data-turbo"]).to eq("false")
  end
end
