require "rails_helper"

RSpec.describe "Navigation" do
  let(:user) { create(:user, name: "Demo Dispatcher") }
  let(:pages) do
    { "Board" => "/", "Calls" => "/calls", "Sites" => "/sites", "Cars" => "/cars", "Statistics" => "/statistics" }
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

  it "puts the Menu button before the system's name, and the sections alone under it", :aggregate_failures do
    get "/"

    expect(response.parsed_body.at_css("header button[popovertarget='main-menu'] ~ a.brand")).to be_present
    menu = response.parsed_body.at_css("nav[aria-label='Main']")
    expect(menu.text.squish).to eq(pages.keys.join(" "))
    expect(menu.css("form, button")).to be_empty
  end

  it "ends the header with the user's initials, which open the account menu", :aggregate_failures do
    get "/"

    button = response.parsed_body.at_css("header nav[aria-label='Main'] ~ button[popovertarget='account-menu']")
    expect(button.at_css("[aria-hidden='true']").text.strip).to eq("DD")
    expect(button.text.squish).to eq("DD Account")
    expect(response.parsed_body.at_css("header button[popovertarget='account-menu'] + #account-menu[popover]")).to be_present
    expect(response.parsed_body.css("header .header-bar > *").last[:id]).to eq("account-menu")
  end

  # A popover in the state "auto" closes on Escape, on a click outside it and
  # when the other one opens; any other value leaves it open until its button.
  it "lets either menu close by itself" do
    get "/"

    expect(response.parsed_body.css("header [popover]").map { |menu| [ menu[:id], menu[:popover] ] })
      .to eq([ %w[main-menu auto], %w[account-menu auto] ])
  end

  it "names the signed-in user and their role in the account menu" do
    get "/"

    expect(response.parsed_body.at_css("header #account-menu").text.squish).to include("Demo Dispatcher Dispatcher")
  end

  it "offers the API key page and Sign out in the account menu (AUTH-06, USR-04)", :aggregate_failures do
    get "/"

    menu = response.parsed_body.at_css("header #account-menu")
    expect(menu.css("a").map { |link| [ link.text.strip, link[:href] ] }).to eq([ [ "API key", api_key_path ] ])
    expect(menu.at_css("form[action='#{session_path}'] input[name='_method']")[:value]).to eq("delete")
    expect(menu.at_css("form[action='#{session_path}'] button").text.strip).to eq("Sign out")
  end

  it "marks the API key page as the current page in the account menu" do
    get api_key_path

    expect(response.parsed_body.at_css("#account-menu a[aria-current='page']").text.strip).to eq("API key")
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
