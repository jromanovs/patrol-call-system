require "rails_helper"

# CRW-01: the crew screen installs on a phone as an app.
RSpec.describe "The app manifest" do
  def png_size(name)
    File.binread(Rails.root.join("app/assets/images", name), 24)[16, 8].unpack("NN")
  end

  def icon(name) = ActionController::Base.helpers.image_path(name)

  it "names the app, its colours, its start page and its icons, without a sign-in", :aggregate_failures do
    get pwa_manifest_path(format: :json)

    manifest = response.parsed_body
    expect(manifest).to include("name" => "Patrol Call System", "short_name" => "Patrol", "start_url" => "/",
                                "display" => "standalone", "theme_color" => "#1c2b39", "background_color" => "#f6f8fa")
    expect(manifest["icons"].map { |entry| [ entry["src"], entry["sizes"] ] })
      .to eq([ [ icon("icon-192.png"), "192x192" ], [ icon("icon.png"), "512x512" ], [ icon("icon.png"), "512x512" ] ])
    expect([ png_size("icon-192.png"), png_size("icon.png") ]).to eq([ [ 192, 192 ], [ 512, 512 ] ])
  end

  it "is linked from every page" do
    sign_in_as(create(:user))
    get root_path

    expect(response.parsed_body.at_css("link[rel=manifest]")[:href]).to eq("/manifest.json")
  end
end
