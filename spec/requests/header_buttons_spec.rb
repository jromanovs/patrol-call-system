require "rails_helper"

# 4.3: the three buttons that stand last in the header look alike: an icon or
# a picture, what is chosen, and a chevron; a row of their menus begins with
# an icon.
RSpec.describe "The buttons of the theme, the language and the account in the header" do
  let(:user) { create(:user, name: "Demo Dispatcher") }

  def page = response.parsed_body

  # The name of the icon a picture is drawn by.
  def drawn(picture) = IconsHelper::OUTLINES.key(picture.at_css("path")&.[]("d"))

  # What a button shows, in its order: an icon by its name, anything else by its class.
  def shown(button)
    seen = button.element_children.reject { |part| part["class"].to_s.include?("visually-hidden") }
    seen.map { |part| part.name == "svg" ? drawn(part) : part["class"].to_s.split.first }
  end

  def rows(menu) = page.css("##{menu}-menu button").map { |row| [ drawn(row.at_css("svg")), row.text.squish ] }

  before { sign_in_as(user) }

  it "shows on the theme button the icon of the present theme and a chevron", :aggregate_failures do
    { "system" => "computer-desktop", "light" => "sun", "dark" => "moon" }.each do |theme, icon|
      user.update!(theme:)
      get calls_path

      expect(shown(page.at_css("header button.theme-button"))).to eq([ icon, "chevron-down" ])
    end
  end

  it "shows on the language button a globe, the code of the language and a chevron" do
    get calls_path

    expect(shown(page.at_css("header button.language-button"))).to eq([ "globe-alt", "language-code", "chevron-down" ])
  end

  it "shows on the account button the picture and a chevron" do
    get calls_path

    expect(shown(page.at_css("header button.account-button"))).to eq([ "avatar", "chevron-down" ])
  end

  it "begins every row of the theme menu and of the language menu with an icon", :aggregate_failures do
    get calls_path

    expect(rows("theme")).to eq([ [ "computer-desktop", "System" ], [ "sun", "Light" ], [ "moon", "Dark" ] ])
    expect(rows("language")).to eq([ [ "language", "English" ], [ "language", "Latviešu" ], [ "language", "Русский" ] ])
  end

  it "draws an icon of a button at 20 px, a chevron and an icon of a row at 16 px", :aggregate_failures do
    get calls_path
    sizes = ->(found) { page.css(found).map { |icon| [ icon["width"], icon["height"] ] }.uniq }

    expect(sizes.call("header button.theme-button svg:not(.chevron), header button.language-button svg.globe")).to eq([ %w[ 20 20 ] ])
    expect(sizes.call("header button.header-button svg.chevron, #theme-menu svg, #language-menu svg")).to eq([ %w[ 16 16 ] ])
  end

  it "hides every icon from a screen reader and keeps the names of the three buttons", :aggregate_failures do
    get calls_path
    names = %w[ theme language account ].map { |button| page.at_css("header button.#{button}-button .visually-hidden").text.squish }

    expect(page.css("header .header-bar svg").map { |icon| icon["aria-hidden"] }.uniq).to eq(%w[ true ])
    expect(names).to eq([ "Theme: System", "Language: English", "Account, Demo Dispatcher" ])
  end

  it "has the same buttons on the crew's screen" do
    sign_in_as(create(:user, :crew))
    get crew_path

    expect(%w[ theme language account ].map { |button| shown(page.at_css("header button.#{button}-button")) })
      .to eq([ %w[ computer-desktop chevron-down ], %w[ globe-alt language-code chevron-down ], %w[ avatar chevron-down ] ])
  end

  # The icons are no drawing of the application's own.
  it "keeps the icons beside the name of their set and of its licence" do
    expect(Rails.root.join("app/helpers/icons_helper.rb").read).to include("Heroicons", "MIT licence", "Copyright (c) Tailwind Labs, Inc.")
    expect(Rails.root.join("SPECIFICATION.md").read).to match(/\*\*Heroicons\*\*.*MIT/)
  end
end
