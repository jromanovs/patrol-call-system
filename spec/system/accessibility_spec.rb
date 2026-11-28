require "rails_helper"

# Every main screen passes the rules of WCAG 2.1 A and AA that axe-core
# checks, in the light and in the dark theme (USR-09, SPECIFICATION.md 4.3).
RSpec.describe "Accessibility of the main screens" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let(:dispatcher) { create(:user) }
  let(:site) { create(:guarded_site, name: "Demo Shop 10") }
  let(:waiting) { create(:alarm_call, guarded_site: site, priority: :critical, alarm_type: :panic, sensor_zone: 2) }
  let(:sent) do
    office = create(:guarded_site, name: "Demo Office 4", site_type: :office,
                                   address: create(:address, full_address: "Raiņa bulvāris 19, Rīga, LV-1050"))
    create(:alarm_call, guarded_site: office, priority: :normal).tap do |call|
      CallStep.new(call, dispatcher).dispatch(car)
    end
  end

  def rules = %i[ wcag2a wcag2aa wcag21a wcag21aa ]

  before do
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: true))
    waiting
    sent
  end

  %w[ light dark ].each do |theme|
    context "with the #{theme} theme" do
      it "keeps the sign-in page clean" do
        visit "/up"
        prefer_colour_scheme(theme)
        visit new_session_path

        expect(page.evaluate_script("matchMedia('(prefers-color-scheme: dark)').matches")).to eq(theme == "dark")
        expect(page).to be_axe_clean.according_to(*rules)
      end

      {
        "the board with its map (DSP-05)" => -> { root_path },
        "the list of calls" => -> { calls_path },
        "the form of a new call" => -> { new_call_path },
        "the page of a call" => -> { call_path(sent) },
        "the list of sites" => -> { guarded_sites_path },
        "the page of a site" => -> { guarded_site_path(site) },
        "the list of cars" => -> { patrol_cars_path },
        "the page of a car" => -> { patrol_car_path(car) },
        "the addresses" => -> { addresses_path },
        "the statistics" => -> { statistics_path },
        "the users" => -> { users_path },
        "the tracking of cars" => -> { tracking_path },
        "the profile" => -> { profile_path },
        "the settings" => -> { settings_path }
      }.each do |screen, path|
        it "keeps #{screen} clean" do
          sign_in_as(create(:user, :administrator, theme:))
          visit instance_exec(&path)

          expect(page).to have_current_path(instance_exec(&path)).and have_css("body[data-theme='#{theme}']")
          expect(page).to be_axe_clean.according_to(*rules)
        end
      end

      it "keeps the crew screen clean" do
        sign_in_as(create(:user, :crew, patrol_car: car, theme:))
        visit crew_path

        expect(page).to have_current_path(crew_path).and have_css("body[data-theme='#{theme}']")
        expect(page).to be_axe_clean.according_to(*rules)
      end
    end
  end
end
