require "rails_helper"
require "rake"

RSpec.describe "css:build", type: :task do
  # Text against its background needs 4.5:1, borders of fields and buttons
  # 3:1 against the surface they stand on (WCAG 2.2, 1.4.3 and 1.4.11).
  # Each pair: foreground variable, background variable, minimum ratio.
  pairs = [
    %w[text surface 4.5], %w[text ground 4.5],
    %w[text-muted surface 4.5], %w[text-muted ground 4.5], %w[text-muted critical-row 4.5],
    %w[header-text header 4.5], %w[menu-text header 4.5],
    %w[accent surface 4.5], %w[accent ground 4.5], %w[on-accent accent 4.5], %w[on-accent accent-dark 4.5],
    %w[field-border surface 3.0],
    %w[error surface 4.5], %w[error alert-tint 4.5], %w[notice notice-tint 4.5],
    %w[priority-critical-text priority-critical-fill 4.5], %w[priority-high-text priority-high-fill 4.5],
    %w[priority-normal-text priority-normal-fill 4.5], %w[priority-low-text priority-low-fill 4.5],
    %w[status-pending-text status-pending-fill 4.5], %w[status-dispatched surface 4.5],
    %w[status-on-scene surface 4.5], %w[status-accepted surface 4.5], %w[status-available surface 4.5], %w[status-out-of-service surface 4.5],
    %w[status-closed surface 4.5], %w[status-cancelled surface 4.5],
    %w[marker-text priority-critical-fill 4.5], %w[marker-text priority-high-fill 4.5],
    %w[marker-text marker-normal 4.5], %w[marker-text marker-low 4.5],
    %w[text-muted divider-light 4.5], %w[notice divider-light 4.5], %w[error critical-row 4.5],
    %w[error divider-light 4.5], %w[status-dispatched priority-normal-fill 4.5],
    %w[marker-text status-dispatched 4.5], %w[marker-text notice 4.5], %w[marker-text error 4.5],
    %w[arrival-sent-text arrival-sent-fill 4.5], %w[marker-text arrival-sent 4.5],
    %w[sos-text sos-fill 4.5],
    %w[header-text header-active 4.5], %w[text divider-light 4.5], %w[accent divider-light 3.0],
    # A link in a critical row; the crew's Accept button; the count of free cars.
    %w[accent critical-row 4.5], %w[on-accent notice 4.5], %w[notice surface 4.5]
  ]

  # _colors.scss lists every colour once: its name, the light value, the dark value.
  def self.sets
    listed = Rails.root.join("app/assets/stylesheets/_colors.scss").read.scan(/^\s*"([a-z-]+)":\s*\((#\h{6}),\s*(#\h{6})\)/)
    { light: listed.to_h { |name, light, _| [ name, light ] }, dark: listed.to_h { |name, _, dark| [ name, dark ] } }
  end

  let(:sets) { self.class.sets }

  def luminance(hex)
    red, green, blue = hex.delete("#").scan(/../).map do |channel|
      value = channel.to_i(16) / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  def contrast(first, second)
    lighter, darker = [ luminance(first), luminance(second) ].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  # The minifier joins equal declarations of neighbouring rules under one list
  # of selectors, so a rule is not always found as it is written.
  def declared(css, selector)
    css.scan(/([^{};]+)\{([^{}]*)\}/).select { |selectors, _| selectors.split(",").include?(selector) }
       .flat_map { |_, declarations| declarations.split(";") }
  end

  # The custom properties a rule gives, each colour written in full.
  def properties(declarations)
    declarations.filter_map { |declaration| declaration.match(/\A--([a-z-]+):(#\h{3,6})\z/)&.captures }
                .to_h { |name, value| [ name, value.length == 4 ? value.gsub(/\h/) { |digit| digit * 2 } : value ] }
  end

  it "compiles Sass, adds browser prefixes and minifies the result", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include(".priority-label.priority-critical{", ".status-label.status-out-of-service{",
                           ".status-label.status-closed{", ".status-label.status-cancelled{")
    expect(css).to include(".field .hint{", ".data-table:where(:not(.compact)) td:before{", ".board{", ".statistics{", ".map-canvas{")
    expect(css).to include(".map-marker[data-arrival=waiting]:before{", '.map-marker[data-arrival=on-the-way]:after{content:"→"',
                           '.map-marker[data-arrival=on-site]:after{content:"✓"', '.arrival[data-arrival=waiting]:before{content:"!"',
                           '.arrival[data-arrival=on-the-way]:before{content:"→"', '.arrival[data-arrival=on-site]:before{content:"✓"')
    expect(css).not_to include(".map-marker[data-arrival=waiting]{outline")
    # DYN-16: a hidden state or button of the notice switch stays hidden.
    expect(css).to include(".crew-notices [hidden]{display:none}")
    expect(css.scan(%r{content:"[!→✓?]"/""}).size).to eq(13)
    expect(css).to include("-webkit-text-size-adjust:100%")
    expect(css.lines.count).to be <= 2
  end

  it "marks a call sent and not accepted, red after 5 minutes, and frames its card (CRW-06)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read)
      .to include('.map-marker[data-arrival=sent]:after{content:"?"', '.map-marker[data-arrival=unanswered]:after{content:"?"',
                  '.arrival[data-arrival=sent]:before{content:"?"', '.arrival[data-arrival=unanswered]:before{content:"?"',
                  ".call-card:has(.arrival[data-arrival=unanswered])")
  end

  it "warns of an arrival far from the site, frames its card and marks one without a position (CRW-09)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read)
      .to include('.map-marker[data-arrival=far]:after{content:"!"', '.map-marker[data-arrival=no-position]:after{content:"✓"',
                  '.arrival[data-arrival=far]:before{content:"!"', '.arrival[data-arrival=no-position]:before{content:"✓"',
                  ".call-card:has(.arrival[data-arrival=far])")
  end

  it "opens the account menu and, in a narrow window, the sections as a card under the header (4.3)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    # A card: placed from the top of the page and scrolled inside itself in a low window.
    expect(css).to include(".account-menu:popover-open{position:absolute;display:flex;",
                           ".main-menu[popover]:popover-open{position:absolute;display:flex;",
                           "max-height:calc(100dvh - 4.5rem);overflow-y:auto;",
                           "inset:3.875rem max(1.5rem,(100% - 87.5rem)/2) auto auto;", ".account-menu:popover-open{right:.375rem}",
                           "inset:3.875rem auto auto .375rem;")
    # Closed: the sections hidden in a narrow window; nothing shows the account menu.
    expect(css).to include("@media (max-width:47.99rem){.main-menu[popover]{display:none}")
    expect(css).not_to include(".account-menu{")
    expect(css).to include(".menu-button+.brand .icon{display:none}", ".brand:first-child{margin-left:.625rem}")
    expect(css).to match(/\.avatar\{[^}]*border-radius:50%;background-color:var\(--accent\);color:var\(--on-accent\)/)
  end

  it "shows the Menu button only in a narrow window and keeps the account button last (4.3)", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include("@media (max-width:47.99rem){.menu-button{display:flex}}", ".account-button{margin-left:auto}",
                           "@media (max-width:47.99rem){.account-button .icon{display:none}}")
    expect(css.index(".header-button{")).to be < css.index(".menu-button{display:none}")
    expect(css.index(".menu-button{display:none}")).to be < css.index(".menu-button{display:flex}")
    # The link of the system's name is no wider than its text.
    expect(css).not_to match(/\.brand\{[^}]*flex-grow/)
  end

  it "keeps keyboard focus seen on the header and inside the cards, and marks a button whose menu is open (4.3)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read)
      .to include(".brand:focus-visible,.header-button:focus-visible{outline-color:var(--header-text)}",
                  ".main-menu a:focus-visible{outline-color:var(--header-text)}",
                  ".account-menu a:focus-visible,.account-menu button:focus-visible{outline-color:var(--accent);outline-offset:-3px}",
                  ".main-menu a:focus-visible{outline-color:var(--accent);outline-offset:-3px}",
                  ".account-button:has(+.account-menu:popover-open),.menu-button:has(~.main-menu:popover-open){background-color:var(--header-active)}")
  end

  it "lets sections that do not fit go on to a second line, and draws no window closer together (4.3)", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include(".main-menu ul{display:flex;flex-wrap:wrap;")
    # Four sections need no closer header; the rule made for seven is gone.
    expect(css).not_to include("63.99rem")
  end

  it "sets the groups of the account menu apart and names the administrator's one (4.3)", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include(".account-menu ul+.account-group,.account-menu ul+ul{border-top:1px solid var(--divider-light)}")
    expect(css).to match(/\.account-group\{[^}]*color:var\(--text-muted\);[^}]*text-transform:uppercase/)
    expect(css).not_to include(".account-menu li+li{")
  end

  it "puts the settings side by side where the window has room for two (4.3)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read)
      .to include(".settings{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(20rem,100%),1fr));", ".settings .setting-card{margin:0}")
  end

  it "shows who the user is beside large initials, and each thing of theirs as a row with its action (USR-05)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read)
      .to include(".profile-card .avatar{width:6rem;height:6rem;font-size:2rem}",
                  ".profile-rows .row{display:grid;grid-template-columns:8.75rem 1fr auto;",
                  "@media (max-width:47.99rem){.profile-rows .row{grid-template-columns:1fr}}")
  end

  it "breaks a long address of the profile inside its card (4.3)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read).to match(/\.profile-who\{[^}]*overflow-wrap:anywhere/)
  end

  it "fills the circle with a photo, hides what is marked hidden, and shows the picture large in its dialog (USR-07)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include(".avatar[hidden]{display:none}", ".picture-preview .avatar{width:9rem;height:9rem;font-size:3rem}",
                           ".user-cell .avatar{display:inline-flex;")
    expect(css).to match(/\.avatar\{[^}]*object-fit:cover/)
  end

  it "sets the warning of a dialog apart, and the card of a password beside the form of a user (USR-08)", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include(".caution{margin:0 0 1rem;padding:.625rem .75rem;border:1px solid var(--arrival-sent-border);border-radius:.5rem;" \
                           "background-color:var(--arrival-sent-fill);color:var(--arrival-sent-text)}")
    # USR-06: among the fields of a form the form's own gap sets it apart.
    expect(declared(css, ".form>.caution")).to eq([ "margin-bottom:0" ])
    expect(declared(css, ".user-edit")).to contain_exactly("display:flex", "flex-wrap:wrap", "align-items:flex-start", "gap:1.5rem")
    expect(declared(css, ".user-edit>form")).to eq([ "flex:1 1 28rem" ])
    expect(declared(css, ".user-edit .setting-card")).to eq([ "flex:0 1 20rem", "margin:0" ])
  end

  it "keeps the empty photo status out of the layout but read by a screen reader (CRW-10)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read).to include(".photo-status:empty{position:absolute;")
  end

  it "marks a car on the map by its call sign framed in the colour of its status (TRK-03)" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    expect(Rails.root.join("app/assets/builds/application.css").read)
      .to include(".car-marker{", ".car-marker[data-status=available]{", ".car-marker[data-status=dispatched]{",
                  ".car-marker[data-status=on-scene]{", ".car-marker[data-status=out-of-service]{")
  end

  it "gives a page the light colours, and the dark ones where it is marked dark or follows a device that asks for dark (4.3)",
     :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(sets[:light].size).to eq(47)
    expect(properties(declared(css, ":root"))).to eq(sets[:light])
    expect(properties(declared(css, ":root[data-theme=dark]"))).to eq(sets[:dark])
    device = css[/@media \(prefers-color-scheme:dark\)\{:root\[data-theme=system\]\{([^}]*)\}\}/, 1].to_s.split(";")
    expect(properties(device)).to eq(sets[:dark])
    # The browser draws its own parts of a page to match: fields, lists, scroll bars.
    expect(declared(css, ":root")).to include("color-scheme:light")
    expect(declared(css, ":root[data-theme=dark]")).to include("color-scheme:dark")
    expect(device).to include("color-scheme:dark")
  end

  it "names a colour in every rule and writes its value in the sets alone (4.3)", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    rules = Rails.root.join("app/assets/builds/application.css").read.gsub(/:root(\[data-theme=[a-z]+\])?\{[^}]*\}/, "")
    # Shadows and the backdrop of a dialog: black or near black, mostly clear, the same in both sets.
    written = rules.scan(/#\h{3,8}\b|(?:rgb|hsl)a?\([^)]*\)/).uniq
    expect(written).to contain_exactly("rgba(31,35,40,.18)", "rgba(31,35,40,.2)", "rgba(0,0,0,.35)", "rgba(0,0,0,.4)")
    expect(rules.scan(/[:, ](?:white|black|red|green|blue|gr[ae]y|yellow|orange|purple)(?=[;}, !])/)).to be_empty
    # A name that stands for no listed colour would leave its rule without one, and no error.
    expect(rules.scan(/var\(--([a-z-]+)\)/).flatten.uniq - sets[:light].keys).to be_empty
  end

  # The details of a site stand on the surface of the page's set, not on the
  # white of the map library, so that their text keeps its contrast in both.
  it "puts the details of a site on the map on the surface colour, the tip included (4.3)", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(declared(css, ".map-canvas .maplibregl-popup-content")).to eq([ "background-color:var(--surface)" ])
    sides = { "top" => "bottom", "top-left" => "bottom", "top-right" => "bottom", "bottom" => "top", "bottom-left" => "top",
              "bottom-right" => "top", "left" => "right", "right" => "left" }
    sides.each do |anchor, side|
      tip = declared(css, ".map-canvas .maplibregl-popup-anchor-#{anchor} .maplibregl-popup-tip")
      expect(tip).to eq([ "border-#{side}-color:var(--surface)" ]), anchor
    end
  end

  sets.each do |theme, colours|
    pairs.each do |foreground, background, minimum|
      it "keeps #{foreground} on #{background} at #{minimum}:1 or more in the #{theme} colours" do
        ratio = contrast(colours.fetch(foreground), colours.fetch(background))

        expect(ratio.round(2)).to be >= minimum.to_f
      end
    end
  end
end
