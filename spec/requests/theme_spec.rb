require "rails_helper"

RSpec.describe "The choice of the theme (USR-09)" do
  let(:user) { create(:user, name: "Demo Dispatcher") }

  def page = response.parsed_body

  # The mark stands on the body: a visit that keeps the page's html element
  # brings a new body, and so the theme of the user who has just signed in.
  def marked = page.at_css("body")["data-theme"]

  it "lets a page without a signed-in user follow the device, with no button to choose", :aggregate_failures do
    get new_session_path

    expect(marked).to eq("system")
    expect(page.at_css("header .theme-button")).to be_nil
  end

  it "asks a visitor who is not signed in to sign in" do
    patch theme_path, params: { theme: "dark" }

    expect(response).to redirect_to(new_session_path)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    it "starts a user with the theme of the device" do
      get root_path

      expect(marked).to eq("system")
    end

    it "has a theme button before the language button and the account button, named by the present choice", :aggregate_failures do
      get calls_path

      buttons = page.css("header .header-bar > button.header-button").map { |button| button["popovertarget"] }
      expect(buttons.last(3)).to eq(%w[ theme-menu language-menu account-menu ])
      button = page.at_css("header button.theme-button")
      expect([ button["type"], button.at_css(".visually-hidden").text.squish ]).to eq([ "button", "Theme: System" ])
      expect(button.at_css("svg[aria-hidden=true]")).to be_present
    end

    it "offers System, Light and Dark in a menu without a script, the present one marked", :aggregate_failures do
      user.update!(theme: :dark)
      get root_path

      menu = page.at_css("header #theme-menu[popover=auto][role=group][aria-label=Theme]")
      forms = menu.css("form[action='#{theme_path}']")
      expect(forms.map { |form| form.at_css("button").text.squish }).to eq(%w[ System Light Dark ])
      expect(forms.map { |form| form.at_css("input[name=theme]")["value"] }).to eq(%w[ system light dark ])
      expect(forms.map { |form| form.at_css("input[name=_method]")["value"] }.uniq).to eq(%w[ patch ])
      expect(forms.map { |form| form.at_css("button")["aria-current"] }).to eq([ nil, nil, "true" ])
      # A full load of the page, so that the menu is closed and the map drawn anew.
      expect(forms.map { |form| form["data-turbo"] }.uniq).to eq(%w[ false ])
      expect(page.at_css("html")["data-theme"]).to be_nil
      expect(page.at_css("header button.theme-button .visually-hidden").text.squish).to eq("Theme: Dark")
    end

    it "saves the choice with the user and comes back to the page it was made on", :aggregate_failures do
      patch theme_path, params: { theme: "dark" }, headers: { "HTTP_REFERER" => calls_url }

      expect(response).to have_http_status(:see_other)
      expect(response.location).to eq(calls_url)
      expect(user.reload.theme).to eq("dark")
      follow_redirect!
      expect(marked).to eq("dark")
    end

    it "comes back to the board when the page is not known, or is of another site", :aggregate_failures do
      patch theme_path, params: { theme: "light" }
      expect(response).to redirect_to(root_path)

      patch theme_path, params: { theme: "dark" }, headers: { "HTTP_REFERER" => "https://elsewhere.example/calls" }
      expect(response).to redirect_to(root_path)
    end

    it "keeps the choice wherever the user signs in, and leaves other users theirs", :aggregate_failures do
      other = create(:user)
      patch theme_path, params: { theme: "light" }
      delete session_path

      sign_in_as(user)
      get root_path
      expect(marked).to eq("light")
      delete session_path
      sign_in_as(other)
      get root_path
      expect(marked).to eq("system")
    end

    it "refuses a theme that is none of the three, one sent as a list and none, and changes nothing", :aggregate_failures do
      user.update!(theme: :light)

      [ { theme: "sepia" }, { theme: [ "dark" ] }, { theme: "" }, {} ].each do |sent|
        patch theme_path, params: sent
        expect(response).to have_http_status(:unprocessable_content), sent.inspect
      end
      expect(user.reload.theme).to eq("light")
    end

    it "changes nothing of the user but the theme, whatever else is sent with it" do
      patch theme_path, params: { theme: "dark", role: "administrator", name: "Other Name", user: { role: "administrator" } }

      expect(user.reload.attributes.values_at("role", "name", "theme")).to eq([ "dispatcher", "Demo Dispatcher", "dark" ])
    end
  end

  it "is the crew's too: the button on its screen, and the choice saved", :aggregate_failures do
    crew = create(:user, :crew)
    sign_in_as(crew)
    get crew_path
    expect(page.css("header .header-bar > button.header-button").map { |button| button["popovertarget"] })
      .to eq(%w[ theme-menu language-menu account-menu ])

    patch theme_path, params: { theme: "dark" }
    expect(response).to redirect_to(crew_path)
    expect(crew.reload.theme).to eq("dark")
    follow_redirect!
    expect(marked).to eq("dark")
  end
end
