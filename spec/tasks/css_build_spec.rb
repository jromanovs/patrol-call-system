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
    %w[arrival-sent-text arrival-sent-fill 4.5], %w[marker-text arrival-sent 4.5]
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

  pairs.each do |foreground, background, minimum|
    it "keeps $#{foreground} on $#{background} at #{minimum}:1 or more" do
      ratio = contrast(colours.fetch(foreground), colours.fetch(background))

      expect(ratio.round(2)).to be >= minimum.to_f
    end
  end
end
