require "rails_helper"

RSpec.describe "The map of the main screen (DSP-03, DSP-05, DYN-12)" do
  include_context "without the seeded records"

  let(:map) { "latvia-2026-10-02T142910Z.pmtiles" }
  let(:tried) { false }

  before do
    sign_in_as(create(:user))
    allow(MapBuild).to receive(:new).and_return(instance_double(MapBuild, current: map, attempted_since?: tried))
  end

  def page = response.parsed_body

  def markers = page.css("[data-map-target=site]")

  def site_at(name, **) = create(:guarded_site, name:, address: create(:address, **))

  # A call taken through the steps of the board up to the status asked for.
  def call_for(site, priority, status = :pending, **)
    call = create(:alarm_call, guarded_site: site, priority:, **)
    steps = CallStep.new(call, create(:user))
    steps.dispatch(create(:patrol_car)) if status.in?(%i[ dispatched on_scene ])
    steps.arrive if status == :on_scene
    steps.cancel("Test") if status == :cancelled
    call.reload
  end

  it "draws the current map file of Latvia, opened on Riga, with the credit of 1.6", :aggregate_failures do
    get root_path

    view = page.at_css("[data-controller=map]")
    expect(view["class"].split).to include("map-fill")
    expect(view["data-map-tiles-value"]).to eq("/tiles/#{map}")
    expect(view["data-map-pmtiles-value"]).to eq("/vendor/pmtiles-4.5.0/pmtiles.js")
    expect([ JSON.parse(view["data-map-center-value"]), view["data-map-zoom-value"] ]).to eq([ [ 24.1052, 56.9496 ], "11" ])
    expect(Nokogiri::HTML.fragment(view["data-map-attribution-value"]).text)
      .to eq("© OpenMapTiles © OpenStreetMap contributors")
    expect(page.at_css("link[rel=stylesheet][href='/vendor/maplibre-gl-6.11.2/maplibre-gl.css']")).to be_present
  end

  it "marks every site under an active contract by its most urgent active call, any other white",
     :aggregate_failures do
    office = site_at("Demo Office 1")
    call_for(office, :low)
    call_for(office, :critical, :dispatched)
    call_for(site_at("Demo Shop 2"), :high, :cancelled)
    call_for(site_at("Demo Office 3"), :normal, :on_scene)
    suspended = site_at("Suspended Site")
    call_for(suspended, :critical)
    suspended.suspended!

    get root_path

    expect(markers.map { |site| site.to_h.values_at("data-label", "data-priority", "data-letter", "data-arrival") }).to eq([
      [ "Demo Office 1, critical call", "critical", "C", "on-the-way" ],
      [ "Demo Office 3, normal call", "normal", "N", "on-site" ],
      [ "Demo Shop 2", "none", nil, nil ]
    ])
    expect(page.at_css(".map-counts").text.squish).to eq("3 sites · 2 with an active call")
  end

  it "places each marker at the address of its site" do
    site_at("Demo Office 1", latitude: 56.9512, longitude: 24.104642)

    get root_path

    expect(markers.first.to_h.values_at("data-latitude", "data-longitude")).to eq(%w[ 56.9512 24.104642 ])
  end

  it "shows the site and its active call in the details of a marker", :aggregate_failures do
    site = site_at("Demo Office 1", full_address: "Jēkaba iela 11, Rīga, LV-1050")
    call = travel_to(14.minutes.ago) { call_for(site, :critical, :dispatched, sensor_zone: 2) }

    get root_path

    details = markers.first.at_css(".map-popup")
    expect(details.at_css("a.map-popup-title")[:href]).to eq(guarded_site_path(site))
    expect(details.text.squish).to include("#{site.contract_number} · Jēkaba iela 11, Rīga, LV-1050",
                                           "Critical", "Dispatched", "14 min",
                                           "#{call.patrol_car.call_sign} on the way · dispatched 14 min ago",
                                           "#{call.summary}, #{call.detail}")
    expect(details.at_css("a[href='#{call_path(call)}']").text).to eq("Open the call")
  end

  it "says when a site has no active call" do
    site_at("Demo Office 1")

    get root_path

    expect(markers.first.at_css(".map-popup").text).to include("No active call")
  end

  it "explains the colours of the markers" do
    get root_path

    expect(page.css(".map-legend li").map { |item| item.text.squish })
      .to eq([ "C Critical call", "H High", "N Normal", "L Low", "No active call",
               "Waiting for a car", "Car on the way", "Car on site" ])
  end

  it "follows every change of a call on every open map (DYN-12)", :aggregate_failures do
    get root_path

    expect(page.at_css("turbo-cable-stream-source")["signed-stream-name"])
      .to eq(Turbo::StreamsChannel.signed_stream_name(:board))
    expect(page.at_css("meta[name=turbo-refresh-method]")[:content]).to eq("morph")
    expect(page.at_css("#map-canvas[data-map-target=canvas]").key?("data-turbo-permanent")).to be(true)
  end

  it "is never shown from Turbo's page cache, which would keep a copy of the old map" do
    get root_path

    expect(page.at_css("meta[name=turbo-cache-control]")[:content]).to eq("no-cache")
  end

  it "leaves the map libraries off the other pages, where only the small map controller loads", :aggregate_failures do
    get calls_path

    expect(page.css("link[rel=modulepreload]").pluck(:href).grep(/maplibre|map\/style/)).to eq([])
    expect(page.css("link[rel=stylesheet]").pluck(:href).grep(/maplibre/)).to eq([])
  end

  it "opens on a site when asked from its page", :aggregate_failures do
    site = site_at("Demo Office 1", latitude: 56.9512, longitude: 24.104642)

    get root_path(site: site.id)

    view = page.at_css("[data-controller=map]")
    expect([ JSON.parse(view["data-map-center-value"]), view["data-map-zoom-value"] ]).to eq([ [ 24.104642, 56.9512 ], "15" ])
    expect(view["data-map-open-value"]).to eq(markers.first[:id])
  end

  it "opens on Riga when the site asked for is not on the map" do
    site = create(:guarded_site, :suspended)

    get root_path(site: site.id)

    expect(JSON.parse(page.at_css("[data-controller=map]")["data-map-center-value"])).to eq([ 24.1052, 56.9496 ])
  end

  context "without a map file yet" do
    let(:map) { nil }

    it "keeps the board working, says the map is being prepared and starts the first build (STO-06)",
       :aggregate_failures do
      call_for(site_at("Demo Office 1"), :critical)

      expect { get root_path }.to have_enqueued_job(MapBuildJob)

      expect(page.at_css(".map-waiting").text).to include("Map is being prepared")
      expect(page.at_css("[data-controller=map]")).to be_nil
      expect(page.css(".call-card").size).to eq(1)
    end

    context "when a build was tried within the last hour" do
      let(:tried) { true }

      it "starts no other one, so visits never repeat a failed download", :aggregate_failures do
        expect { get root_path }.not_to have_enqueued_job(MapBuildJob)

        expect(MapBuild.new).to have_received(:attempted_since?).with(be_within(1.second).of(1.hour.ago))
        expect(page.at_css("main").text).to include("Map is being prepared")
      end
    end
  end

  it "leads the old map page address to the main screen, on the site asked for" do
    get map_path(site: 5)

    expect(response).to redirect_to(root_path(site: 5))
  end
end
