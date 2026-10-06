require "rails_helper"

RSpec.describe "Navigation" do
  let(:user) { create(:user, name: "Demo Dispatcher") }
  let(:pages) do
    { "Calls" => "/calls", "Sites" => "/sites", "Cars" => "/cars", "Statistics" => "/statistics" }
  end

  before { sign_in_as(user) }

  it "opens the board from the system's name and marks it as the current page there", :aggregate_failures do
    get "/"
    expect(response.parsed_body.at_css("header a.brand[href='/']")["aria-current"]).to eq("page")

    get "/calls"
    expect(response.parsed_body.at_css("header a.brand[href='/']")["aria-current"]).to be_nil
  end

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
    expect(button.text.squish).to eq("DD Account, Demo Dispatcher")
    expect(button.css("span[aria-hidden]")).to be_empty
    expect(button.at_css(".visually-hidden").text.strip).to eq("Account, Demo Dispatcher")
    expect(response.parsed_body.at_css("header button[popovertarget='account-menu'] + #account-menu[popover]")).to be_present
    expect(response.parsed_body.css("header .header-bar > *").last[:id]).to eq("account-menu")
  end

  # A popover in the state "auto" closes on Escape, on a click outside it and
  # when the other one opens; any other value leaves it open until its button.
  it "lets every menu of the header close by itself" do
    get "/"

    expect(response.parsed_body.css("header [popover]").map { |menu| [ menu[:id], menu[:popover] ] })
      .to eq([ %w[main-menu auto], %w[theme-menu auto], %w[language-menu auto], %w[account-menu auto] ])
  end

  it "names the account menu and hides every icon of the header from a screen reader", :aggregate_failures do
    get "/"

    expect(response.parsed_body.at_css("header #account-menu[role='group'][aria-label='Account']")).to be_present
    expect(response.parsed_body.css("header svg").map { |icon| icon["aria-hidden"] }.uniq).to eq([ "true" ])
  end

  it "names the signed-in user and their role in the account menu" do
    get "/"

    expect(response.parsed_body.at_css("header #account-menu").text.squish).to include("Demo Dispatcher Dispatcher")
  end

  it "offers the API key page and Sign out in the account menu (AUTH-06, USR-04)", :aggregate_failures do
    get "/"

    menu = response.parsed_body.at_css("header #account-menu")
    expect(menu.css("a").map { |link| [ link.text.strip, link[:href] ] })
      .to eq([ [ "Profile", profile_path ], [ "API key", api_key_path ] ])
    expect(menu.at_css("form[action='#{session_path}'] input[name='_method']")[:value]).to eq("delete")
    expect(menu.at_css("form[action='#{session_path}'] button").text.strip).to eq("Sign out")
    expect(menu.text).not_to include("Administration")
  end

  context "when signed in as a supervisor" do
    let(:user) { create(:user, :supervisor) }

    it "has the same sections and no group of the administrator", :aggregate_failures do
      get "/"

      expect(response.parsed_body.css("nav[aria-label='Main'] a").map(&:text)).to eq(pages.keys)
      menu = response.parsed_body.at_css("header #account-menu")
      expect(menu.css("a, button").map { |item| item.text.strip }).to eq([ "Profile", "API key", "Sign out" ])
      expect(menu.text).not_to include("Administration")
    end
  end

  context "when signed in as an administrator" do
    let(:user) { create(:user, :administrator) }

    it "keeps the pages of running the system in a group of the account menu, not among the sections", :aggregate_failures do
      get "/"

      menu = response.parsed_body.at_css("header #account-menu")
      expect(menu.css("a").map { |link| [ link.text.strip, link[:href] ] })
        .to eq([ [ "Profile", profile_path ], [ "API key", api_key_path ], [ "Users", users_path ], [ "Tracking", tracking_path ],
                 [ "Settings", settings_path ] ])
      group = menu.at_css("ul[aria-labelledby]")
      expect(menu.at_css("##{group['aria-labelledby']}").text.strip).to eq("Administration")
      expect(group.css("a").map { |link| link.text.strip }).to eq(%w[Users Tracking Settings])
      expect(menu.css("a, button").map { |item| item.text.strip })
        .to eq([ "Profile", "API key", "Users", "Tracking", "Settings", "Sign out" ])
      expect(response.parsed_body.css("nav[aria-label='Main'] a").map(&:text)).to eq(pages.keys)
    end

    it "marks the page of the group as the current one in the account menu", :aggregate_failures do
      { "Users" => users_path, "Tracking" => tracking_path, "Settings" => settings_path }.each do |label, path|
        get path

        expect(response.parsed_body.css("#account-menu a[aria-current='page']").map { |link| link.text.strip }).to eq([ label ])
      end
    end
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
