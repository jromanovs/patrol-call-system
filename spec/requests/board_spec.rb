require "rails_helper"

RSpec.describe "Board panels over the map (DSP-03, DYN-02)" do
  include_context "without the seeded records"

  before do
    sign_in_as(create(:user))
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: false))
  end

  it "lists every car with its status, free cars first, and counts the free ones", :aggregate_failures do
    create(:patrol_car, call_sign: "P-21", status: :out_of_service)
    create(:patrol_car, call_sign: "P-15")
    create(:patrol_car, call_sign: "P-12")
    get root_path

    panel = response.parsed_body.at_css("aside.board-cars")
    expect(panel.css("li .call-sign").map(&:text)).to eq([ "P-12", "P-15", "P-21" ])
    expect(panel.css("li .status-label").map { |label| label.text.strip }).to eq([ "Available", "Available", "Out of service" ])
    expect(panel.at_css(".count").text).to eq("2 available of 3")
  end

  it "says when there are no cars" do
    get root_path

    expect(response.parsed_body.at_css("aside.board-cars").text).to include("No cars yet.")
  end

  it "names each panel's minimize button and the part it hides", :aggregate_failures do
    get root_path

    buttons = response.parsed_body.css("button.panel-toggle")
    expect(buttons.map { |button| button.to_h.values_at("aria-label", "aria-controls", "aria-expanded") }).to eq([
      [ "Minimize active calls", "calls-body", "true" ],
      [ "Minimize patrol cars", "cars-body", "true" ],
      [ "Minimize legend", "legend-body", "true" ]
    ])
    expect(buttons.map { |button| response.parsed_body.at_css("##{button['aria-controls']}") }).to all(be_present)
  end

  it "keeps the number of calls and of critical ones in the label of the minimized panel", :aggregate_failures do
    site = create(:guarded_site)
    create(:alarm_call, guarded_site: site, priority: :critical)
    create(:alarm_call, guarded_site: site, priority: :low)
    get root_path

    heading = response.parsed_body.at_css(".calls-panel .panel-heading")
    expect(heading.at_css(".panel-count").text.squish).to eq("2")
    expect(heading.at_css(".panel-critical").text.squish).to eq("1 critical")
  end

  it "names no critical calls when there are none" do
    create(:alarm_call, guarded_site: create(:guarded_site), priority: :low)
    get root_path

    expect(response.parsed_body.at_css(".calls-panel .panel-critical")).to be_nil
  end

  it "joins both panels in one sheet with the tabs Calls and Cars for a narrow window", :aggregate_failures do
    create(:patrol_car)
    get root_path

    sheet = response.parsed_body.at_css("#board-panels")
    expect(sheet.css(".sheet-tabs button").map { |tab| [ tab.text.squish, tab["aria-controls"] ] })
      .to eq([ [ "Calls 0", "calls-panel" ], [ "Cars 1 free", "cars-panel" ] ])
    expect(sheet.at_css("button.sheet-handle")["aria-controls"]).to eq("board-panels")
    expect(sheet.css("#calls-panel, #cars-panel").size).to eq(2)
  end
end
