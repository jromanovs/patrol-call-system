require "rails_helper"

RSpec.describe "Statistics" do
  include_context "without the seeded records"

  let(:site) { create(:guarded_site, name: "Warehouse No. 3") }
  let(:september) { { from: "2026-09-01", to: "2026-09-30" } }

  before { sign_in_as(create(:user)) }

  def page(**params)
    get statistics_path, params: params
    response.parsed_body
  end

  # The rows of one results table: the text of every cell.
  def rows(body, section) = body.css("##{section} tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }

  def received(status, arrival: nil, outcome: nil)
    received_at = Time.zone.local(2026, 9, 10, 9, 0)
    create(:alarm_call, guarded_site: site, priority: :critical, received_at:).tap do |call|
      call.update_columns(status: Call.statuses.fetch(status), outcome: outcome && Call.outcomes.fetch(outcome),
                          arrived_at: arrival && received_at + arrival.minutes)
    end
  end

  it "opens from the menu for the current month in Riga time", :aggregate_failures do
    travel_to(Time.zone.local(2026, 10, 15, 12, 0)) do
      create(:alarm_call, guarded_site: site, received_at: Time.zone.local(2026, 10, 1, 0, 5))
      create(:alarm_call, guarded_site: site, received_at: Time.zone.local(2026, 9, 30, 23, 55))
      get root_path
      expect(response.parsed_body.at_css("nav.main-menu a:contains('Statistics')")["href"]).to eq(statistics_path)

      body = page
      expect([ body.at_css("#from")["value"], body.at_css("#to")["value"] ]).to eq(%w[ 2026-10-01 2026-10-31 ])
      expect(body.at_css("#statistics-results .count").text).to eq("1 call")
    end
  end

  it "takes the month of Riga time right after midnight on its first day" do
    travel_to(Time.zone.local(2026, 11, 1, 0, 30)) do
      body = page
      expect([ body.at_css("#from")["value"], body.at_css("#to")["value"] ]).to eq(%w[ 2026-11-01 2026-11-30 ])
    end
  end

  it "shows the four calculations of the chosen calls (CALC-01 … CALC-04)", :aggregate_failures do
    received("closed", arrival: 10, outcome: "false_alarm")
    body = page(**september)

    expect(rows(body, "by-status")).to include([ "Closed", "1" ])
    expect(body.at_css("#by-status tfoot td:last-child").text).to eq("1")
    expect(rows(body, "by-outcome")).to include([ "False alarm", "1" ])
    expect(rows(body, "response")).to include([ "All calls", "1", "10.0 min" ], [ "Critical", "1", "10.0 min" ])
    expect(rows(body, "response-by-car")).to be_empty
    expect(body.at_css("#false-alarms .share").text.squish).to eq("100.0 %, 1 of 1 closed calls")
    expect(rows(body, "false-alarm-sites")).to eq([ [ "Warehouse No. 3", site.contract_number, "1" ] ])
  end

  it "shows a dash, not an error, without arrivals or closed calls (CALC-02, CALC-03)", :aggregate_failures do
    received("pending")
    body = page(**september)

    expect(rows(body, "response").first).to eq([ "All calls", "0", "—" ])
    expect(body.at_css("#false-alarms .share").text.squish).to eq("—, no closed calls")
    expect(body.at_css("#false-alarm-sites").text).to include("No false alarms")
  end

  it "takes the filter of the call list and links back to the same calls (FLT-01)", :aggregate_failures do
    get calls_path, params: { status: "closed", sort: "site", direction: "asc" }
    expect(response.parsed_body.at_css("#calls-list a.statistics-link")["href"]).to eq(statistics_path(status: "closed"))

    body = page(status: "closed", **september)
    expect(body.at_css("#statistics-results a.calls")["href"]).to eq(calls_path(status: "closed", **september))
  end

  it "reloads only the results on a filter change (DYN-06)", :aggregate_failures do
    body = page
    expect(body.at_css("form.filters")["data-turbo-frame"]).to eq("statistics-results")
    expect(body.at_css("turbo-frame#statistics-results[data-turbo-action=advance]")).to be_present

    get statistics_path, params: september, headers: { "Turbo-Frame" => "statistics-results" }
    expect(response.parsed_body.at_css("header.site-header")).to be_nil
  end

  it "offers Clear only while a filter is chosen", :aggregate_failures do
    expect(page.at_css("#statistics-results a.clear")).to be_nil
    expect(page(status: "closed").at_css("#statistics-results a.clear")["href"]).to eq(statistics_path)
  end

  it "names an N outside 1 to 50 (CALC-04)" do
    expect(page(top: "0").at_css("#statistics-results .field-error").text).to eq("Number of sites must be from 1 to 50")
  end

  it "gives every field a label and a hint (DSP-04)" do
    expect(fields_without_label_or_hint(page)).to be_empty
  end

  it "sends a visitor without a sign-in to the sign-in page" do
    delete session_path
    get statistics_path

    expect(response).to redirect_to(new_session_path)
  end
end
