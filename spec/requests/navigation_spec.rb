require "rails_helper"

RSpec.describe "Navigation" do
  let(:pages) do
    { "Board" => "/", "Calls" => "/calls", "Sites" => "/sites", "Cars" => "/cars", "Map" => "/map" }
  end

  it "shows the main menu with every section in order" do
    get "/"

    links = response.parsed_body.css("nav[aria-label='Main'] a")
    expect(links.map { |link| [ link.text, link["href"] ] }).to eq(pages.to_a)
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
