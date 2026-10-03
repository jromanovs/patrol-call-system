require "rails_helper"

RSpec.describe "The tracking page of the administrator (TRK-01, TRK-02, BR-20)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }

  def page = response.parsed_body

  def rows = page.css("table.tracking tbody tr").to_h { |row| [ row.at_css("th").text.squish, row ] }

  describe "as the administrator" do
    before { sign_in_as(create(:user, :administrator)) }

    it "is in the menu and offers each car its position source, saved as soon as it is chosen", :aggregate_failures do
      car.update!(position_source: :crew_phone)
      get tracking_path

      expect(page.css(".main-menu a").map(&:text)).to include("Tracking")
      expect(page.at_css("button[role=switch]")).to be_nil
      form = rows["P-12"].at_css("form[action='#{tracking_car_source_path(car)}']")
      expect([ form["data-controller"], form.at_css("input[name=_method]")["value"] ]).to eq(%w[ auto-submit patch ])
      select = form.at_css("select[name=position_source]")
      expect(select.css("option").map { |option| [ option["value"], option.text, option.key?("selected") ] })
        .to eq([ [ "not_tracked", "Not tracked", false ], [ "traccar", "Traccar Client", false ], [ "crew_phone", "Crew's phone", true ] ])
      expect(select["data-action"]).to eq("change->auto-submit#submit")
      expect(form.at_css("label[for='#{select['id']}']").text).to eq("Position source of P-12")
    end

    it "saves a car's source, says so, and tells the open main and crew screens", :aggregate_failures do
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      messages = %w[ crew_phone traccar not_tracked ].map do |source|
        patch tracking_car_source_path(car), params: { position_source: source }
        [ response.location, flash[:notice], car.reload.position_source ]
      end

      expect(messages).to eq([ [ tracking_url, "P-12 is tracked by the crew's phone", "crew_phone" ],
                               [ tracking_url, "P-12 is tracked by Traccar Client", "traccar" ],
                               [ tracking_url, "P-12 is not tracked", "not_tracked" ] ])
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:board).exactly(3).times
    end

    it "refuses a source that is none of the three", :aggregate_failures do
      patch tracking_car_source_path(car), params: { position_source: "satellite" }

      expect(flash[:alert]).to eq("Choose a position source")
      expect(car.reload).to be_not_tracked
    end

    it "lists every car with what its source needs and its last position", :aggregate_failures do
      car.update!(position_source: :traccar)
      car.issue_tracking_key
      create(:car_position, patrol_car: car, recorded_at: 61.seconds.ago)
      create(:patrol_car, call_sign: "P-07", position_source: :crew_phone)
      create(:patrol_car, call_sign: "P-21")
      get tracking_path

      cells = rows.transform_values { |row| row.css("td").drop(1).map { |cell| cell.text.squish } }
      expect(cells["P-12"]).to eq([ car.reload.tracking_key_hint, "1 min ago", "New identifier for P-12" ])
      expect(cells["P-07"]).to eq([ "not needed", "Never", "" ])
      expect(cells["P-21"]).to eq([ "—", "Never", "" ])
      expect(page.text.squish).to include("Server URL #{traccar_url}")
    end

    it "offers a first identifier to a car tracked by Traccar Client without one" do
      car.update!(position_source: :traccar)
      get tracking_path

      expect(rows["P-12"].css("td").last.text.squish).to eq("Issue identifier for P-12")
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

    patch tracking_car_source_path(car), params: { position_source: "traccar" }
    post tracking_car_key_path(car)
    expect(car.reload).to have_attributes(position_source: "not_tracked", tracking_key_digest: nil)
  end
end
