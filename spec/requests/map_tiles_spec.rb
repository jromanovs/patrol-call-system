require "rails_helper"

RSpec.describe "The map file" do
  let(:published) { MapBuild::FOLDER.join("published") }
  let(:map) { published.join("latvia-2026-10-02.pmtiles") }

  before do
    published.mkpath
    map.write("PMTiles-test-data")
    MapBuild::FOLDER.join("sources").mkpath
    MapBuild::FOLDER.join("sources/latvia.osm.pbf").write("extract")
  end

  after { FileUtils.rm_rf(MapBuild::FOLDER) }

  it "is served in the pieces the browser asks for, and kept by browsers, its name being dated (STO-06)",
     :aggregate_failures do
    get "/tiles/latvia-2026-10-02.pmtiles", headers: { "Range" => "bytes=0-6" }

    expect(response).to have_http_status(:partial_content)
    expect(response.body).to eq("PMTiles")
    expect(response.headers["Cache-Control"]).to eq("public, max-age=31536000, immutable")
  end

  it "never serves the sources of the build" do
    get "/tiles/../sources/latvia.osm.pbf"

    expect(response).to have_http_status(:not_found)
  end
end
