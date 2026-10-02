require "rails_helper"

RSpec.describe "Navigation" do
  let(:user) { create(:user, name: "Demo Dispatcher") }
  let(:pages) do
    { "Board" => "/", "Calls" => "/calls", "Sites" => "/sites", "Cars" => "/cars", "Map" => "/map",
      "Statistics" => "/statistics" }
  end

  before { sign_in_as(user) }

  it "shows the main menu with every section in order" do
    get "/"

    links = response.parsed_body.css("nav[aria-label='Main'] ul a")
    expect(links.map { |link| [ link.text, link["href"] ] }).to eq(pages.to_a)
  end

  it "opens the menu from the Menu button in a narrow window", :aggregate_failures do
    get "/"

    button = response.parsed_body.at_css("header button[popovertarget]")
    expect(button&.text&.strip).to eq("Menu")
    expect(response.parsed_body.at_css("nav##{button['popovertarget']}[popover][aria-label='Main']")).to be_present
  end

  it "names the signed-in user and their role in the header" do
    get "/"

    expect(response.parsed_body.at_css("header .signed-in").text.squish).to include("Demo Dispatcher Dispatcher")
  end

  it "opens every section and marks it as the current page in the menu", :aggregate_failures do
    pages.each do |label, path|
      get path

      expect(response).to have_http_status(:ok)
      current = response.parsed_body.css("nav[aria-label='Main'] a[aria-current='page']")
      expect(current.map(&:text)).to eq([ label ])
    end
  end
end
