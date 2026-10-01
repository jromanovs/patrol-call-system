require "rails_helper"

RSpec.describe "layouts/application" do
  subject(:page) do
    ApplicationController.render(html: "<p>Probe content</p>".html_safe, layout: "application")
  end

  it "wraps the content in a full HTML document" do
    expect(page).to start_with("<!DOCTYPE html>")
  end

  it "shows the system name in the header when nobody is signed in" do
    expect(Nokogiri::HTML5(page).at_css("header").text).to include("Patrol Call System")
  end

  it "shows the application name as the default title" do
    expect(page).to include("<title>Patrol Call System</title>")
  end

  it "renders the page content in the main area after the menu" do
    expect(page).to match(%r{</header>\s*<main>\s*<p>Probe content</p>\s*</main>})
  end
end
