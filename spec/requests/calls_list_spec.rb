require "rails_helper"

RSpec.describe "Calls list" do
  include_context "without the seeded records"

  let(:site) { create(:guarded_site, name: "Warehouse No. 3") }
  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let!(:call) { create(:alarm_call, guarded_site: site, alarm_type: :fire, sensor_zone: 7, received_at: Time.zone.local(2026, 10, 1, 9, 0)) }

  before { sign_in_as(create(:user)) }

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

  it "says when no call matches and offers the reset (FLT-03)", :aggregate_failures do
    get calls_path, params: { status: "closed" }

    expect(response.parsed_body.at_css("#calls-list").text).to include("No calls match the filter")
    expect(response.parsed_body.at_css("#calls-list a.clear")["href"]).to eq(calls_path)
  end

  it "names a period whose start is after its end (FLT-02)" do
    get calls_path, params: { from: "2026-10-02", to: "2026-10-01" }

    expect(response.parsed_body.at_css("#calls-list .field-error").text).to eq("Period start is after period end")
  end

  it "gives every filter a label and a hint (DSP-04)" do
    get calls_path

    expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
  end

  describe "the call page (DSP-02)" do
    it "shows the attributes, the timeline with the minutes between steps and the people", :aggregate_failures do
      dispatcher = create(:user, name: "Night Dispatcher")
      travel_to(Time.zone.local(2026, 10, 1, 9, 5)) { CallStep.new(call, dispatcher).dispatch(car) }
      travel_to(Time.zone.local(2026, 10, 1, 9, 17)) { CallStep.new(call.reload, dispatcher).arrive }
      get call_path(call)

      details = response.parsed_body.css("dl.details div").to_h { |row| [ row.at_css("dt").text, row.at_css("dd").text.squish ] }
      expect(details).to include("Call" => "Alarm: fire, Zone 7", "Site" => "Warehouse No. 3", "Car" => "P-12",
                                 "Dispatched by" => "Night Dispatcher", "Status" => "On scene")
      expect(details["Received"]).to eq("01.10.2026 09:00")
      expect(details["Dispatched"]).to eq("01.10.2026 09:05, 5 min after receipt")
      expect(details["Arrived"]).to eq("01.10.2026 09:17, 12 min after dispatch; response time 17.0 min")
    end
  end
end
