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
    %w[header-text header-active 4.5], %w[text divider-light 4.5], %w[accent divider-light 3.0]
  ]

  let(:colours) do
    Rails.root.join("app/assets/stylesheets/_colors.scss").read.scan(/^\$([a-z-]+):\s*(#\h{6});/).to_h
  end

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
    expect(css).to match(/\.avatar\{[^}]*border-radius:50%;background-color:#0b5cad;color:#fff/)
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
      .to include(".brand:focus-visible,.header-button:focus-visible{outline-color:#fff}", ".main-menu a:focus-visible{outline-color:#fff}",
                  ".account-menu a:focus-visible,.account-menu button:focus-visible{outline-color:#0b5cad;outline-offset:-3px}",
                  ".main-menu a:focus-visible{outline-color:#0b5cad;outline-offset:-3px}",
                  ".account-button:has(+.account-menu:popover-open),.menu-button:has(~.main-menu:popover-open){background-color:#2c3f52}")
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
    expect(css).to include(".account-menu ul+.account-group,.account-menu ul+ul{border-top:1px solid #eef1f4}")
    expect(css).to match(/\.account-group\{[^}]*color:#59636e;[^}]*text-transform:uppercase/)
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

  pairs.each do |foreground, background, minimum|
    it "keeps $#{foreground} on $#{background} at #{minimum}:1 or more" do
      ratio = contrast(colours.fetch(foreground), colours.fetch(background))

      expect(ratio.round(2)).to be >= minimum.to_f
    end
  end
end
