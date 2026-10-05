require "rails_helper"

RSpec.describe "The settings page of the administrator (TRK-05, DEL-09)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }

  def page = response.parsed_body

  def positions = page.at_css("section[aria-labelledby=positions-kept-title]")

  def calls = page.at_css("section[aria-labelledby=calls-kept-title]")

  context "when signed in as the administrator" do
    before { sign_in_as(create(:user, :administrator)) }

    it "stands in the group Administration of the account menu, marked there as the current page", :aggregate_failures do
      get settings_path

      expect(response).to have_http_status(:ok)
      expect(page.at_css("main h1").text).to eq("Settings")
      expect(page.css("#account-menu ul[aria-labelledby] a").map { |link| [ link.text.strip, link[:href] ] })
        .to eq([ [ "Users", users_path ], [ "Tracking", tracking_path ], [ "Settings", settings_path ] ])
      expect(page.css("#account-menu a[aria-current='page']").map { |link| link.text.strip }).to eq([ "Settings" ])
    end

    it "gives every field a label and a hint, each field with a name of its own (DSP-04)", :aggregate_failures do
      get settings_path

      expect(fields_without_label_or_hint(page)).to be_empty
      expect(page.css("main input[type=number]").map { |field| field["id"] }).to eq(%w[ position_months call_months ])
    end

    describe "how long car positions are kept (TRK-05, BR-20)" do
      it "shows the period in months with its rule, and since when positions are kept", :aggregate_failures do
        create(:car_position, patrol_car: car, recorded_at: Time.zone.local(2020, 1, 1),
                              created_at: Time.utc(2026, 10, 2, 21, 30))
        create(:car_position, patrol_car: car)
        get settings_path

        expect(positions.at_css("h2").text).to eq("How long car positions are kept")
        expect(positions.at_css("label[for=position_months]").text.squish).to eq("Keep positions for")
        expect(positions.at_css("input#position_months[type=number][min='3']")["value"]).to eq("24")
        expect(positions.text.squish).to include(
          "Not less than 3 months. Every night at 03:30 the positions older than this are deleted.",
          "Kept now: positions since 03.10.2026.", "The main map shows a car at its last position of the last 30 days"
        )
      end

      it "says so when no position is kept yet" do
        get settings_path

        expect(positions.text.squish).to include("No position is kept yet.")
      end

      it "saves a longer period at once and says so", :aggregate_failures do
        patch settings_positions_path, params: { position_months: "36" }

        expect(response).to have_http_status(:see_other)
        expect([ response.location, flash[:notice] ]).to eq([ settings_url, "Car positions are kept for 36 months" ])
        expect(Setting.current.position_months).to eq(36)
      end

      it "refuses a period below 3 months beside its own field, which keeps what was typed", :aggregate_failures do
        patch settings_positions_path, params: { position_months: "2" }

        expect(response).to have_http_status(:unprocessable_content)
        field = positions.at_css("input#position_months[aria-invalid=true]")
        expect([ field["value"], field["aria-describedby"] ]).to eq([ "2", "position-months-hint position-months-error" ])
        expect(positions.at_css("#position-months-error").text).to eq("Keep positions for at least 3 months")
        expect([ calls.at_css(".field-error"), calls.at_css("input#call_months")["value"] ]).to eq([ nil, "24" ])
        expect(Setting.current.position_months).to eq(24)
      end

      it "refuses a wrong period also when the question is said to be answered, or nothing is sent", :aggregate_failures do
        [ { position_months: "2", shorter: "yes" }, { position_months: "many", shorter: "yes" }, { shorter: "yes" },
          {} ].each do |sent|
          patch settings_positions_path, params: sent

          expect(response).to have_http_status(:unprocessable_content)
          expect(positions.at_css("#position-months-error").text).to eq("Keep positions for at least 3 months")
        end
        expect(Setting.current.position_months).to eq(24)
      end

      it "refuses a period beyond 1200 months", :aggregate_failures do
        patch settings_positions_path, params: { position_months: "1201" }

        expect(positions.at_css("#position-months-error").text).to eq("Keep positions for at most 1200 months")
        expect(Setting.current.position_months).to eq(24)
      end

      it "saves the period in force again without a question" do
        patch settings_positions_path, params: { position_months: "24" }

        expect(flash[:notice]).to eq("Car positions are kept for 24 months")
      end

      it "asks before a shorter period, naming what goes and the oldest position kept", :aggregate_failures do
        create(:car_position, patrol_car: car, created_at: Time.zone.local(2025, 8, 3, 9, 0))
        patch settings_positions_path, params: { position_months: "6" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css("dialog #dialog-title").text).to eq("Keep positions for 6 months only?")
        expect(page.at_css("dialog").text.squish).to include(
          "Positions older than 6 months will be deleted tonight at 03:30 and cannot be restored.",
          "The oldest kept now is of 03.08.2025."
        )
        expect(Setting.current.position_months).to eq(24)
      end

      it "puts the question, with its answer, into the dialog of the open page", :aggregate_failures do
        patch settings_positions_path, params: { position_months: "6" }, as: :turbo_stream
        answer = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[action=replace][target=modal] template")

        expect(answer.inner_html).to include("Keep positions for 6 months only?", 'value="Keep 6 months"')
        expect(answer.inner_html).to include('name="position_months"', 'name="shorter"')
      end

      it "gives the answer's hidden fields no ids, so that the page's own field keeps its", :aggregate_failures do
        patch settings_positions_path, params: { position_months: "6" }

        expect(page.css("dialog form input[type=hidden]").map { |field| field["name"] } - %w[ _method authenticity_token ])
          .to eq(%w[ position_months shorter ])
        expect(page.css("dialog form input[id]")).to be_empty
      end

      it "saves the shorter period once it is confirmed, and deletes nothing itself", :aggregate_failures do
        create(:car_position, patrol_car: car, created_at: 14.months.ago)
        patch settings_positions_path, params: { position_months: "6" }
        form = page.at_css("dialog form")
        answer = form.css("input[type=hidden][name]").to_h { |field| [ field["name"], field["value"] ] }.except("_method")

        expect([ form["action"], form.at_css("input[type=submit]")["value"] ]).to eq([ settings_positions_path, "Keep 6 months" ])
        expect { patch form["action"], params: answer }.not_to change(CarPosition, :count)
        expect(flash[:notice]).to eq("Car positions are kept for 6 months")
        expect(Setting.current.position_months).to eq(6)
      end
    end

    describe "how long calls are kept (DEL-09, BR-23)" do
      it "shows the period in months with its rule and the first day still kept", :aggregate_failures do
        travel_to(Time.zone.local(2026, 10, 5, 12, 0)) { get settings_path }

        expect(calls.at_css("h2").text).to eq("How long calls are kept")
        expect(calls.at_css("label[for=call_months]").text.squish).to eq("Keep calls for")
        expect(calls.at_css("input#call_months[type=number][min='3']")["value"]).to eq("24")
        expect(calls.text.squish).to include(
          "Calls are kept for 24 months: a call received on 05.10.2024 or later cannot be deleted.",
          "Not less than 3 months. Nothing is deleted by itself: the period only allows a deletion by hand, " \
          "on the page Delete old calls or on a call's page."
        )
      end

      it "saves a period and says so; a shorter one asks nothing and deletes nothing", :aggregate_failures do
        patch settings_calls_path, params: { call_months: "36" }
        expect(response).to have_http_status(:see_other)
        expect([ response.location, flash[:notice] ]).to eq([ settings_url, "Calls are kept for 36 months" ])

        expect { patch settings_calls_path, params: { call_months: "12" } }.not_to change(Call, :count)
        expect(flash[:notice]).to eq("Calls are kept for 12 months")
        expect(Setting.current.call_months).to eq(12)
      end

      it "refuses a period below 3 months or beyond 1200, or none, beside its own field", :aggregate_failures do
        { "2" => "least 3", "1201" => "most 1200", "" => "least 3" }.each do |months, bound|
          patch settings_calls_path, params: { call_months: months }

          expect(response).to have_http_status(:unprocessable_content)
          expect(calls.at_css("#call-months-error").text).to eq("Keep calls for at #{bound} months")
          expect([ calls.at_css("input#call_months[aria-invalid=true]")["value"], calls.at_css(".kept-now").text.squish ])
            .to match([ months, a_string_including("Calls are kept for 24 months") ])
          expect(positions.at_css(".field-error")).to be_nil
        end
        expect(Setting.current.call_months).to eq(24)
      end
    end
  end

  it "is the administrator's only: nobody else opens it or sets a period", :aggregate_failures do
    [ create(:user, :supervisor), create(:user), create(:user, :crew), nil ].each do |user|
      user ? sign_in_as(user) : delete(session_path)
      get settings_path
      expect(response).not_to have_http_status(:ok), (user&.role || "signed out")

      patch settings_positions_path, params: { position_months: "36" }
      patch settings_calls_path, params: { call_months: "36" }
      expect([ Setting.current.position_months, Setting.current.call_months ]).to eq([ 24, 24 ]), (user&.role || "signed out")
    end
    expect(response).to redirect_to(new_session_path)
  end

  it "tells a supervisor why the page does not open, and why a period is not saved", :aggregate_failures do
    sign_in_as(create(:user, :supervisor))

    get settings_path
    expect(flash[:alert]).to eq("Not allowed for your role")
    get calls_path
    patch settings_calls_path, params: { call_months: "36" }
    expect(flash[:alert]).to eq("Not allowed for your role")
  end

  it "has left the former addresses of the two forms", :aggregate_failures do
    sign_in_as(create(:user, :administrator))

    [ "/tracking/retention", "/calls/retention" ].each do |former|
      patch former, params: { months: "36" }

      expect(response).to have_http_status(:not_found), former
    end
    expect([ Setting.current.position_months, Setting.current.call_months ]).to eq([ 24, 24 ])
  end
end
