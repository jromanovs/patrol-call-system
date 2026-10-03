require "rails_helper"

RSpec.describe "Calls list" do
  include_context "without the seeded records"

  let(:site) { create(:guarded_site, name: "Warehouse No. 3") }
  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let!(:call) { create(:alarm_call, guarded_site: site, alarm_type: :fire, sensor_zone: 7, received_at: Time.zone.local(2026, 10, 1, 9, 0)) }
  let(:dispatcher) { create(:user, name: "Night Dispatcher") }

  before { sign_in_as(create(:user)) }

  def step(minute) = travel_to(Time.zone.local(2026, 10, 1, 9, minute)) { yield CallStep.new(call.reload, dispatcher) }

  it "lists the calls with the count and a link to each call (DSP-01)", :aggregate_failures do
    get calls_path

    expect(response.parsed_body.at_css("#calls-list .count").text).to eq("1 call")
    expect(response.parsed_body.at_css("td[data-label='Site'] a")["href"]).to eq(call_path(call))
  end

  it "filters in place and keeps the filter in the page address (DYN-06)", :aggregate_failures do
    get calls_path, params: { status: "pending" }

    form = response.parsed_body.at_css("form.filters")
    expect(form["data-turbo-frame"]).to eq("calls-list")
    expect(form.css("select[data-action='change->auto-submit#submit']").map { |select| select["name"] })
      .to eq(%w[status priority kind district site_id car_id])
    expect(response.parsed_body.at_css("turbo-frame#calls-list[data-turbo-action=advance] table")).to be_present
    expect(response.parsed_body.at_css("#calls-list a.clear")["href"]).to eq(calls_path)
  end

  it "searches while typing and has no search button (DYN-06)", :aggregate_failures do
    get calls_path

    form = response.parsed_body.at_css("form.filters")
    expect(form.at_css("input[type=search]")["data-action"]).to eq("input->auto-submit#submit")
    expect(form.css("input[type=date]").map { |field| field["data-action"] }).to all(eq("change->auto-submit#submit"))
    expect(form.css("input[type=submit], button[type=submit]")).to be_empty
  end

  it "answers a filter with the list alone (DYN-06)", :aggregate_failures do
    get calls_path, params: { q: "warehouse" }, headers: { "Turbo-Frame" => "calls-list" }

    expect(response.parsed_body.at_css("turbo-frame#calls-list .count").text).to eq("1 call")
    expect(response.parsed_body.at_css("header.site-header")).to be_nil
  end

  it "keeps the filter in the sort links; the first click on Received shows the oldest first (SRT-01)",
     :aggregate_failures do
    get calls_path, params: { status: "pending" }

    links = response.parsed_body.css("#calls-list th a").to_h do |link|
      [ link.text, Rack::Utils.parse_query(URI(link["href"]).query) ]
    end
    expect(links["Received"]).to eq("status" => "pending", "sort" => "received_at", "direction" => "asc")
    expect(links["Priority"]).to eq("status" => "pending", "sort" => "priority", "direction" => "asc")
    expect(links.keys).to eq(%w[ Received Priority Site Call Status Car Outcome Time Response ])
  end

  it "says when no call matches and offers the reset (FLT-03)", :aggregate_failures do
    get calls_path, params: { status: "closed" }

    expect(response.parsed_body.at_css("#calls-list").text).to include("No calls match the filter")
    expect(response.parsed_body.at_css("#calls-list a.clear")["href"]).to eq(calls_path)
  end

  it "asks for 2 characters and keeps the whole list for a shorter text (FLT-01)", :aggregate_failures do
    get calls_path, params: { q: "w" }

    expect(response.parsed_body.at_css("#calls-list .field-error").text).to eq("Enter at least 2 characters")
    expect(response.parsed_body.at_css("#calls-list .count").text).to eq("1 call")
  end

  it "names a period whose start is after its end (FLT-02)" do
    get calls_path, params: { from: "2026-10-02", to: "2026-10-01" }

    expect(response.parsed_body.at_css("#calls-list .field-error").text).to eq("Period start is after period end")
  end

  it "gives every filter a label and a hint (DSP-04)" do
    get calls_path

    expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
  end

  describe "the times of a call (DSP-01)" do
    def row
      get calls_path
      response.parsed_body.at_css("#calls-list tbody tr")
    end

    it "shows the handling time and the response time of a finished call", :aggregate_failures do
      step(5) { |steps| steps.dispatch(car) }
      step(17, &:arrive)
      step(30) { |steps| steps.close("false_alarm", "") }

      cells = row
      expect(cells.at_css("td[data-label=Time]").text.squish).to eq("30 min")
      expect(cells.at_css("td[data-label=Time] [data-waiting-target]")).to be_nil
      expect(cells.at_css("td[data-label=Response]").text.squish).to eq("17.0 min")
    end

    it "recounts the handling time of an active call every minute in the browser (DYN-03)", :aggregate_failures do
      cells = travel_to(Time.zone.local(2026, 10, 1, 9, 25)) { row }

      expect(cells.at_css("td[data-label=Time]").text.squish).to eq("25 min")
      expect(cells.at_css("td[data-label=Time] [data-waiting-target=minutes]")["data-received-at"])
        .to eq(call.received_at.iso8601)
      expect(cells.at_css("td[data-label=Response]").text.squish).to eq("—")
      expect(response.parsed_body.at_css("#calls-list table")["data-controller"]).to eq("waiting")
    end
  end

  describe "the call page (DSP-02)" do
    let(:details) do
      get call_path(call)
      response.parsed_body.css("dl.details div").to_h { |row| [ row.at_css("dt").text, row.at_css("dd").text.squish ] }
    end

    it "shows the attributes, the timeline with the minutes between steps and the people", :aggregate_failures do
      step(5) { |steps| steps.dispatch(car) }
      step(7, &:accept)
      step(17, &:arrive)

      expect(details["Accepted"]).to eq("01.10.2026 09:07, 2 min after dispatch")
      expect(details).to include("Call" => "Alarm: fire, Zone 7", "Site" => "Warehouse No. 3", "Car" => "P-12",
                                 "Dispatched by" => "Night Dispatcher", "Status" => "On scene")
      expect(details["Received"]).to eq("01.10.2026 09:00")
      expect(details["Dispatched"]).to eq("01.10.2026 09:05, 5 min after receipt")
      expect(details["Arrived"]).to eq("01.10.2026 09:17, 12 min after dispatch; response time 17.0 min")
    end

    it "shows the status as a label" do
      get call_path(call)

      expect(response.parsed_body.at_css("dl.details .status-label.status-pending")&.text).to eq("Pending")
    end

    it "counts the closing from the arrival and the whole call from receipt", :aggregate_failures do
      step(5) { |steps| steps.dispatch(car) }
      step(17, &:arrive)
      step(30) { |steps| steps.close("false_alarm", "") }

      expect(details["Closed"]).to eq("01.10.2026 09:30, 13 min later")
      expect(details["Total"]).to eq("30 min")
    end

    it "counts an active call until now" do
      travel_to(Time.zone.local(2026, 10, 1, 9, 25)) { details }

      expect(details["Total"]).to eq("25 min so far")
    end

    it "counts a cancellation after dispatch from the dispatch" do
      step(5) { |steps| steps.dispatch(car) }
      step(10) { |steps| steps.cancel("Client called back") }

      expect(details["Cancelled"]).to eq("01.10.2026 09:10, 5 min later")
    end

    it "drops the seconds in the step and in the total alike", :aggregate_failures do
      travel_to(call.received_at + 29.minutes + 40.seconds) { CallStep.new(call, dispatcher).cancel("Client called back") }

      expect(details["Cancelled"]).to eq("01.10.2026 09:29, 29 min later")
      expect(details["Total"]).to eq("29 min")
    end
  end
end
