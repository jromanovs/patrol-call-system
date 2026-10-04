require "rails_helper"

RSpec.describe "The tracking page of the administrator (TRK-01, TRK-02, BR-20)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }

  def page = response.parsed_body

  def rows = page.css("table.tracking tbody tr").to_h { |row| [ row.at_css("td[data-label=Car]").text.squish, row ] }

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
      expect(select["aria-describedby"]).to eq("source-hint")
      expect(page.at_css("#source-hint ~ table.tracking")).to be_present
      expect(page.at_css("#source-hint").text.squish).to eq("A choice is saved at once.")
    end

    it "shows each car as a card on a phone: every cell names its column, one without an action stays out",
       :aggregate_failures do
      car.update!(position_source: :crew_phone)
      get tracking_path

      expect(page.at_css("table.tracking")["class"].split).to eq(%w[ data-table tracking ])
      expect(rows["P-12"].css("td").map { |cell| cell["data-label"] })
        .to eq([ "Car", "Position source", "Device identifier", "Last position", nil ])
    end

    it "saves a car's source, says so, and tells the open main and crew screens", :aggregate_failures do
      car
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      messages = %w[ crew_phone traccar not_tracked ].map do |source|
        patch tracking_car_source_path(car), params: { position_source: source }
        [ response.location, flash[:notice], car.reload.position_source ]
      end

      expect(messages).to eq([ [ tracking_url, "P-12 is tracked by the crew's phone", "crew_phone" ],
                               [ tracking_url, "P-12 is tracked by Traccar Client", "traccar" ],
                               [ tracking_url, "P-12 is not tracked", "not_tracked" ] ])
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:board, any_args).exactly(3).times
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

      cells = rows.transform_values { |row| row.css("td").drop(2).map { |cell| cell.text.squish } }
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

    describe "an identifier for Traccar Client (TRK-02)" do
      before { car.update!(position_source: :traccar) }

      def issued = page.at_css(".tracking-key")

      it "is shown once after it is issued, with Copy, the steps and Done, and kept only as its digest",
         :aggregate_failures do
        post tracking_car_key_path(car)
        expect(response).to redirect_to(tracking_path)
        carried = response.headers["Set-Cookie"].to_s
        follow_redirect!

        key = issued.at_css("code.secret").text
        expect(PatrolCar.find_by_tracking_key(key)).to eq(car)
        # On its way to the page the identifier travels unreadable.
        expect(carried).not_to include(key)
        expect(issued.at_css("h2").text).to eq("New identifier of P-12 — shown only this once")
        expect(issued.css("ol li").map { |step| step.text.squish })
          .to eq([ "Press Copy.",
                   "In Traccar Client open Settings: paste it as Device identifier; Server URL #{traccar_url}; " \
                   "Location accuracy: high.",
                   "Switch tracking on in Traccar Client, then press Done here." ])
        expect(issued.at_css("a.button", text: "Done")["href"]).to eq(tracking_path)
        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      it "is copied by a button that says so", :aggregate_failures do
        post tracking_car_key_path(car)
        follow_redirect!

        expect(issued["data-controller"]).to eq("clipboard")
        expect(issued.at_css("code.secret")["data-clipboard-target"]).to eq("source")
        button = issued.at_css("button[type=button]")
        expect([ button.text.squish, button["data-action"], button["data-clipboard-target"] ]).to eq(%w[ Copy clipboard#copy button ])
        # Only what the copying came to is read out, not the whole block.
        expect(issued["role"]).to be_nil
        expect(issued.at_css("p[role=status][data-clipboard-target=status]").text).to eq("")
      end

      it "is not shown again after a reload, which issues no new one", :aggregate_failures do
        post tracking_car_key_path(car)
        follow_redirect!
        key = issued.at_css("code.secret").text

        get tracking_path
        expect(issued).to be_nil
        expect(page.text).not_to include(key)
        expect(PatrolCar.find_by_tracking_key(key)).to eq(car)
      end

      it "is issued only for a car tracked by Traccar Client", :aggregate_failures do
        car.update!(position_source: :crew_phone)
        post tracking_car_key_path(car)

        expect(flash[:alert]).to eq("P-12 is not tracked by Traccar Client")
        expect(car.reload.tracking_key_digest).to be_nil
      end

      it "is copied by a controller the page loads" do
        get tracking_path

        expect(JSON.parse(page.at_css("script[type=importmap]").text)["imports"]).to have_key("controllers/clipboard_controller")
      end

      it "is replaced only after a confirmation; the first is issued without one", :aggregate_failures do
        get tracking_path
        expect(rows["P-12"].at_css("form[action='#{tracking_car_key_path(car)}']")["data-turbo-confirm"]).to be_nil

        car.issue_tracking_key
        get tracking_path
        expect(rows["P-12"].at_css("form[action='#{tracking_car_key_path(car)}']")["data-turbo-confirm"])
          .to eq("Replace the identifier of P-12? The current one stops working at once.")
      end
    end
  end

  describe "how long car positions are kept (TRK-05, BR-20)" do
    before { sign_in_as(create(:user, :administrator)) }

    def section = page.at_css("section[aria-labelledby=tracking-kept-title]")

    it "shows the period in months with its rule, and since when positions are kept", :aggregate_failures do
      create(:car_position, patrol_car: car, recorded_at: Time.zone.local(2020, 1, 1),
                            created_at: Time.utc(2026, 10, 2, 21, 30))
      create(:car_position, patrol_car: car)
      get tracking_path

      expect(section.at_css("h2").text).to eq("How long car positions are kept")
      expect(section.at_css("label[for=months]").text.squish).to eq("Keep positions for")
      expect(section.at_css("input#months[type=number][min='3']")["value"]).to eq("24")
      expect(section.text.squish).to include(
        "Not less than 3 months. Every night at 03:30 the positions older than this are deleted.",
        "Kept now: positions since 03.10.2026.", "The main map shows a car at its last position of the last 30 days"
      )
    end

    it "says so when no position is kept yet" do
      get tracking_path

      expect(section.text.squish).to include("No position is kept yet.")
    end

    it "saves a longer period at once and says so", :aggregate_failures do
      patch tracking_retention_path, params: { months: "36" }

      expect(response).to redirect_to(tracking_path)
      expect(flash[:notice]).to eq("Car positions are kept for 36 months")
      expect(Setting.current.position_months).to eq(36)
    end

    it "refuses a period below 3 months beside the field, which keeps what was typed", :aggregate_failures do
      patch tracking_retention_path, params: { months: "2" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(section.at_css("input#months[aria-invalid=true]")["value"]).to eq("2")
      expect(section.at_css("input#months")["aria-describedby"]).to eq("months-hint months-error")
      expect(section.at_css("#months-error").text).to eq("Keep positions for at least 3 months")
      expect(Setting.current.position_months).to eq(24)
    end

    it "refuses a wrong period also when the question is said to be answered, or nothing is sent", :aggregate_failures do
      [ { months: "2", shorter: "yes" }, { months: "many", shorter: "yes" }, { shorter: "yes" }, {} ].each do |sent|
        patch tracking_retention_path, params: sent

        expect(response).to have_http_status(:unprocessable_content)
        expect(section.at_css("#months-error").text).to eq("Keep positions for at least 3 months")
      end
      expect(Setting.current.position_months).to eq(24)
    end

    it "refuses a period beyond 1200 months", :aggregate_failures do
      patch tracking_retention_path, params: { months: "1201" }

      expect(section.at_css("#months-error").text).to eq("Keep positions for at most 1200 months")
      expect(Setting.current.position_months).to eq(24)
    end

    it "saves the period in force again without a question" do
      patch tracking_retention_path, params: { months: "24" }

      expect(flash[:notice]).to eq("Car positions are kept for 24 months")
    end

    it "shows the last position of a car also when it is older than the map's 30 days" do
      create(:car_position, patrol_car: car, recorded_at: Time.zone.local(2026, 8, 20, 12, 0))
      travel_to(Time.zone.local(2026, 10, 4, 12, 0)) { get tracking_path }

      expect(rows["P-12"].at_css("td[data-label='Last position']").text.squish).to eq("20.08.2026 12:00")
    end

    it "asks before a shorter period, naming what goes and the oldest position kept", :aggregate_failures do
      create(:car_position, patrol_car: car, created_at: Time.zone.local(2025, 8, 3, 9, 0))
      patch tracking_retention_path, params: { months: "6" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css("dialog #dialog-title").text).to eq("Keep positions for 6 months only?")
      expect(page.at_css("dialog").text.squish).to include(
        "Positions older than 6 months will be deleted tonight at 03:30 and cannot be restored.",
        "The oldest kept now is of 03.08.2025."
      )
      expect(Setting.current.position_months).to eq(24)
    end

    it "puts the question, with its answer, into the dialog of the open page", :aggregate_failures do
      patch tracking_retention_path, params: { months: "6" }, as: :turbo_stream
      answer = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[action=replace][target=modal] template")

      expect(answer.inner_html).to include("Keep positions for 6 months only?", 'value="Keep 6 months"')
      expect(answer.inner_html).to include('name="months"', 'name="shorter"')
    end

    it "gives the answer's hidden fields no ids, so that the page's own field keeps its", :aggregate_failures do
      patch tracking_retention_path, params: { months: "6" }

      expect(page.css("dialog form input[type=hidden][name=months], dialog form input[type=hidden][name=shorter]").size).to eq(2)
      expect(page.css("dialog form input[id]")).to be_empty
    end

    it "saves the shorter period once it is confirmed, and deletes nothing itself", :aggregate_failures do
      create(:car_position, patrol_car: car, created_at: 14.months.ago)
      patch tracking_retention_path, params: { months: "6" }
      form = page.at_css("dialog form")
      answer = form.css("input[type=hidden][name]").to_h { |field| [ field["name"], field["value"] ] }.except("_method")

      expect(form.at_css("input[type=submit]")["value"]).to eq("Keep 6 months")
      expect { patch form["action"], params: answer }.not_to change(CarPosition, :count)
      expect(flash[:notice]).to eq("Car positions are kept for 6 months")
      expect(Setting.current.position_months).to eq(6)
    end
  end

  it "is the administrator's only", :aggregate_failures do
    sign_in_as(create(:user, :supervisor))
    get tracking_path
    expect(flash[:alert]).to eq("Not allowed for your role")

    patch tracking_car_source_path(car), params: { position_source: "traccar" }
    expect(car.reload).to be_not_tracked

    car.update!(position_source: :traccar)
    post tracking_car_key_path(car)
    expect(car.reload.tracking_key_digest).to be_nil

    patch tracking_retention_path, params: { months: "36" }
    expect(Setting.current.position_months).to eq(24)
  end
end
