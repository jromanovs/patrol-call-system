require "rails_helper"
require "open3"

# DSP-05, 4.3: the style of the map is a script of the browser. Node runs the same file
# here, so that its colours are held by an example as the stylesheet's are.
RSpec.describe "MapStyle" do
  def run(script, *arguments)
    # Node's remark on a package without a stated kind of module is no part of the answer.
    quiet = { "NODE_NO_WARNINGS" => "1" }
    output, status = Open3.capture2(quiet, "node", "--input-type=module", "-e", script, *arguments, chdir: Rails.root.to_s)
    raise "node failed" unless status.success?

    JSON.parse(output)
  end

  def paints(theme)
    run('import { style } from "./app/javascript/map/style.js"; ' \
        'const made = style("pmtiles://map", "credit", process.argv[1]); ' \
        "console.log(JSON.stringify(Object.fromEntries(made.layers.map((layer) => [ layer.id, layer.paint ]))))", theme)
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

  it "draws the light map as before, also when no theme or an unknown one is named", :aggregate_failures do
    light = paints("light")

    expect(light.dig("ground", "background-color")).to eq("#eef0ec")
    expect(light.dig("water", "fill-color")).to eq("#a8cbe0")
    expect(light.dig("road-major", "line-color")).to eq("#fbe3b4")
    expect(light.dig("place-major").values_at("text-color", "text-halo-color")).to eq(%w[ #59636e #ffffff ])
    expect(paints("sepia")).to eq(light)
    expect(paints("")).to eq(light)
  end

  it "draws the same layers in dark colours on a dark page", :aggregate_failures do
    light = paints("light")
    dark = paints("dark")

    expect(dark.keys).to eq(light.keys)
    expect(dark.dig("ground", "background-color")).to eq("#1b1f24")
    expect(dark.dig("water", "fill-color")).to eq("#0f2a3d")
    expect(dark.dig("road-minor", "line-color")).to eq("#3a4048")
    colours = ->(paints) { paints.values.flat_map(&:values).grep(/\A#\h{6}\z/).uniq }
    expect(colours.call(dark) & colours.call(light)).to be_empty
  end

  it "keeps the names of places read on the ground of either map: 4.5:1 or more", :aggregate_failures do
    %w[ light dark ].each do |theme|
      made = paints(theme)
      ratio = contrast(made.dig("place-major", "text-color"), made.dig("ground", "background-color"))

      expect(ratio.round(2)).to be >= 4.5, theme
    end
  end

  it "takes a page for dark when it is marked dark, or follows a device that asks for dark" do
    answers = run('import { dark } from "./app/javascript/map/style.js"; ' \
                  'console.log(JSON.stringify([ [ "dark", false ], [ "dark", true ], [ "system", true ], [ "system", false ], ' \
                  '[ "light", true ], [ "light", false ], [ undefined, true ] ].map(([ mark, device ]) => dark(mark, device))))')

    expect(answers).to eq([ true, true, true, false, false, false, false ])
  end
end
