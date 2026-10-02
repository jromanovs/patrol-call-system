require "rails_helper"

# CRW-01: the crew screen installs on a phone as an app.
RSpec.describe "The app manifest" do
  def png_size(path)
    File.binread(Rails.public_path.join(path.delete_prefix("/")), 24)[16, 8].unpack("NN")
  end

  it "names the app, its colours, its start page and its icons, without a sign-in", :aggregate_failures do
    get pwa_manifest_path(format: :json)

    manifest = response.parsed_body
    expect(manifest).to include("name" => "Patrol Call System", "short_name" => "Patrol", "start_url" => "/",
                                "display" => "standalone", "theme_color" => "#1c2b39", "background_color" => "#f6f8fa")
    expect(manifest["icons"].map { |icon| [ icon["src"], icon["sizes"], png_size(icon["src"]) ] })
      .to eq([ [ "/icon-192.png", "192x192", [ 192, 192 ] ], [ "/icon.png", "512x512", [ 512, 512 ] ],
               [ "/icon.png", "512x512", [ 512, 512 ] ] ])
  end

  it "is linked from every page" do
    sign_in_as(create(:user))
    get root_path

    expect(response.parsed_body.at_css("link[rel=manifest]")[:href]).to eq("/manifest.json")
  end
end
