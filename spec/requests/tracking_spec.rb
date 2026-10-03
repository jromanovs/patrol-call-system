require "rails_helper"

RSpec.describe "The tracking page of the administrator (TRK-01, TRK-02, BR-20)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }

  def page = response.parsed_body

  describe "as the administrator" do
    before { sign_in_as(create(:user, :administrator)) }

    it "is in the menu and switches tracking on and off", :aggregate_failures do
      get tracking_path
      expect(page.css(".main-menu a").map(&:text)).to include("Tracking")
      switch = page.at_css("button[role=switch]")
      expect([ switch["aria-checked"], switch.text.squish ]).to eq([ "false", "Track the patrol cars Off" ])

      patch tracking_path, params: { car_tracking: "1" }
      expect(response).to redirect_to(tracking_path)
      expect(Setting.current).to be_car_tracking

      follow_redirect!
      expect(page.at_css("button[role=switch]")["aria-checked"]).to eq("true")
      patch tracking_path, params: { car_tracking: "0" }
      expect(Setting.current).not_to be_car_tracking
    end

    it "lists every car with its identifier's hint and its last position", :aggregate_failures do
      car.issue_tracking_key
      create(:patrol_car, call_sign: "P-21")
      create(:car_position, patrol_car: car, recorded_at: 61.seconds.ago)
      get tracking_path

      rows = page.css("table.tracking tbody tr").to_h { |row| [ row.at_css("th").text.squish, row.css("td").map { |cell| cell.text.squish } ] }
      expect(rows["P-12"]).to eq([ car.reload.tracking_key_hint, "1 min ago", "New identifier" ])
      expect(rows["P-21"]).to eq([ "—", "Never", "Issue identifier" ])
      expect(page.text.squish).to include("Server URL: #{traccar_url}")
    end

    it "shows a new identifier once, with what to set in Traccar Client, and keeps only its digest",
       :aggregate_failures do
      post tracking_car_key_path(car)

      key = page.at_css("code.secret").text
      expect(PatrolCar.find_by_tracking_key(key)).to eq(car)
      expect(page.text.squish).to include("P-12", "Copy the identifier now: it is shown only this once.",
                                          traccar_url, "Location accuracy: high")
      expect(response.headers["Cache-Control"]).to include("no-store")

      get tracking_path
      expect(page.text).not_to include(key)
    end
  end

  it "is the administrator's only", :aggregate_failures do
    sign_in_as(create(:user, :supervisor))
    get tracking_path
    expect(flash[:alert]).to eq("Not allowed for your role")

    patch tracking_path, params: { car_tracking: "1" }
    post tracking_car_key_path(car)
    expect([ Setting.current.car_tracking?, car.reload.tracking_key_digest ]).to eq([ false, nil ])
  end
end
