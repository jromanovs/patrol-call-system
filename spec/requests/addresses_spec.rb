require "rails_helper"

RSpec.describe "Address suggestions (DYN-11)" do
  include_context "without the seeded records"

  before do
    create(:address, code: 101_838_146, full_address: "Jēkaba iela 11, Rīga, LV-1050")
    sign_in_as(create(:user))
  end

  def suggestions(text)
    get addresses_path, params: { q: text }
    response.parsed_body.at_css("turbo-frame#address-suggestions")
  end

  it "offers the matching addresses as choices for the address field", :aggregate_failures do
    choice = suggestions("jekaba 11").at_css("button[data-action='address-picker#choose']")

    expect(choice.text.strip).to eq("Jēkaba iela 11, Rīga, LV-1050")
    expect(choice["data-address-id"]).to eq(Address.find_by!(code: 101_838_146).id.to_s)
    expect(choice["data-address-label"]).to eq("Jēkaba iela 11, Rīga, LV-1050")
  end

  it "asks for 3 characters or more" do
    expect(suggestions("je").text).to include("Enter at least 3 characters")
  end

  it "says when nothing is found" do
    expect(suggestions("nowhere street").text).to include("No address found")
  end

  it "shows the source of the addresses (1.6)" do
    expect(suggestions("jekaba").text).to include("State Address Register")
  end
end
