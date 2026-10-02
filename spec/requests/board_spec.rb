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
    expect(buttons.map do |button|
      button.to_h.values_at("aria-label", "aria-controls", "aria-expanded", "data-action", "data-board-panel-param")
    end).to eq([
      [ "Active calls panel", "calls-body", "true", "board#toggle", "calls" ],
      [ "Legend panel", "legend-body", "true", "board#toggle", "legend" ],
      [ "Patrol cars panel", "cars-body", "true", "board#toggle", "cars" ]
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

    create(:alarm_call, guarded_site: create(:guarded_site), priority: :critical)
    get root_path

    sheet = response.parsed_body.at_css("#board-panels")
    expect(sheet.css(".sheet-tabs button").map { |tab| tab.to_h.values_at("aria-controls", "data-action", "data-board-tab-param") })
      .to eq([ %w[ calls-panel board#showTab calls ], %w[ cars-panel board#showTab cars ] ])
    expect(sheet.css(".sheet-tabs button").map { |tab| tab.text.squish }).to eq([ "Calls 1 1 critical", "Cars 1 free" ])
    expect(sheet.at_css("button.sheet-handle").to_h.values_at("aria-controls", "data-action"))
      .to eq(%w[ board-panels board#toggleSheet ])
    expect(sheet.css("#calls-panel, #cars-panel").size).to eq(2)
  end

  it "fills the window only on the main screen", :aggregate_failures do
    get root_path
    expect(response.parsed_body.at_css("body")["class"]).to eq("main-screen")

    get calls_path
    expect(response.parsed_body.at_css("body")["class"]).to be_nil
  end

  it "joins the board to the map: a call's site and a marker name the same site", :aggregate_failures do
    site = create(:guarded_site)
    create(:alarm_call, guarded_site: site)
    get root_path

    page = response.parsed_body
    card = page.at_css(".call-card")
    expect(page.at_css(".board")["data-controller"]).to eq("board")
    expect(page.at_css(".board")["data-action"]).to eq("map:picked@window->board#mark")
    expect(card.at_css(".call-card-site").to_h.values_at("data-action", "data-board-site-param"))
      .to eq([ "board#show", card["data-site"] ])
    expect(page.at_css("[data-map-target=site]##{card['data-site']}")).to be_present
  end

  it "draws the panels as the user left them, from the choices kept in cookies", :aggregate_failures do
    cookies["board_callsPanel"] = "minimized"
    cookies["board_sheet"] = "lowered"
    cookies["board_sheetTab"] = "cars"
    cookies["board_carsPanel"] = "anything"
    get root_path

    expect(response.parsed_body.at_css("html").to_h.slice("data-calls-panel", "data-sheet", "data-sheet-tab", "data-cars-panel"))
      .to eq("data-calls-panel" => "minimized", "data-sheet" => "lowered", "data-sheet-tab" => "cars")
    expect(response.parsed_body.at_css('button.panel-toggle[aria-controls="calls-body"]')["aria-expanded"]).to eq("false")
  end

  it "names the site in a card as plain text while there is no map to show it on" do
    allow(MapBuild).to receive(:new).and_return(instance_double(MapBuild, current: nil, attempted_since?: true))
    create(:alarm_call, guarded_site: create(:guarded_site, name: "Office North"))
    get root_path

    expect(response.parsed_body.at_css(".call-card [data-label=Site] .primary").text).to eq("Office North")
  end
end
