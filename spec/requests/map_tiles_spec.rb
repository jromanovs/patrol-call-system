require "rails_helper"

RSpec.describe "The map file" do
  # Only the files of this spec are made and removed: a developer's own map
  # in the same folder stays.
  let(:map) { MapBuild::FOLDER.join("published/latvia-2000-01-01T000000Z.pmtiles") }
  let(:source) { MapBuild::FOLDER.join("sources/spec-only.osm.pbf") }

  before do
    [ map, source ].each do |path|
      path.dirname.mkpath
      path.write("PMTiles-test-data")
    end
  end

  after { [ map, source ].each { |path| path.delete if path.exist? } }

  context "when signed in" do
    before { sign_in_as(create(:user)) }

    it "is served as binary data, in the pieces the browser asks for, and kept by browsers (STO-06)",
       :aggregate_failures do
      get "/tiles/latvia-2000-01-01T000000Z.pmtiles", headers: { "Range" => "bytes=0-6" }

      expect(response).to have_http_status(:partial_content)
      expect(response.body).to eq("PMTiles")
      expect(response.headers["Content-Type"]).to eq("application/octet-stream")
      expect(response.headers["Cache-Control"]).to eq("private, max-age=31536000, immutable")
    end

    it "never serves the sources of the build" do
      get "/tiles/../sources/spec-only.osm.pbf"

      expect(response).to have_http_status(:not_found)
    end
  end

  it "is not served without a sign-in (BR-13)" do
    get "/tiles/latvia-2000-01-01T000000Z.pmtiles"

    expect(response).to have_http_status(:not_found)
  end
end
