require "rails_helper"

# The app icon is named by an address that changes with its picture: public
# files are served to be kept for a year, so a fixed address would leave
# browsers on whatever picture they kept first.
RSpec.describe "The app icon" do
  let(:icon_address) { %r{\A/assets/icon(-192)?-\h{8}\.(png|svg)\z} }

  it "is taken from addresses that change with the picture, on every page", :aggregate_failures do
    get new_session_path

    links = response.parsed_body.css("link[rel=icon], link[rel=apple-touch-icon]").map { |link| link[:href] }
    expect(links).to eq([ ActionController::Base.helpers.image_path("icon.png"),
                          ActionController::Base.helpers.image_path("icon.svg"),
                          ActionController::Base.helpers.image_path("icon.png") ])
    expect(links).to all(match(icon_address))
  end

  it "is no longer served at the fixed addresses a browser may have kept" do
    expect(%w[ icon.png icon.svg icon-192.png ].select { |name| Rails.public_path.join(name).exist? }).to eq([])
  end

  it "is named by no page, script or setting at those fixed addresses" do
    named = Rails.root.glob("{app,config}/**/*.{rb,haml,erb,js}").select do |file|
      file.read.match?(%r{["'(]/icon(-192)?\.(png|svg)})
    end

    expect(named.map { |file| file.relative_path_from(Rails.root).to_s }).to eq([])
  end

  # An iPhone adding the app from a browser other than Safari asks only
  # these names; kept a day, so that a new picture reaches it soon.
  %w[ /apple-touch-icon.png /apple-touch-icon-precomposed.png ].each do |path|
    it "is served at the iPhone's own name #{path}, without a sign-in, kept a day", :aggregate_failures do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.body.b).to eq(Rails.root.join("app/assets/images/icon.png").binread)
      expect(response.headers["Cache-Control"]).to match(/\bmax-age=86400\b/).and include("public")
    end
  end

  it "is served at those names to a signed-in crew too, not led to its screen" do
    sign_in_as(create(:user, :crew))

    get "/apple-touch-icon.png"

    expect([ response.status, response.media_type ]).to eq([ 200, "image/png" ])
  end

  it "is the shield of the header, not the red circle", :aggregate_failures do
    svg = Rails.root.join("app/assets/images/icon.svg").read

    expect(svg).to include('fill="#1c2b39"', "M12 3l7 3v5c0 4.5-3 8.5-7 10-4-1.5-7-5.5-7-10V6l7-3z")
    expect(svg).not_to include("circle")
  end
end
