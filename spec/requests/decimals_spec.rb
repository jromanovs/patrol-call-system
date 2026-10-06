require "rails_helper"

RSpec.describe "A number with a decimal part is written as the language of the page writes it (USR-10)" do
  include_context "without the seeded records"

  let(:received) { Time.zone.local(2026, 9, 10, 9, 0) }
  let(:dispatcher) { create(:user) }
  # Closed as a false alarm; its car arrived seven and a half minutes after it was received.
  let(:call) do
    create(:alarm_call, guarded_site: create(:guarded_site, name: "Demo Office 1"), received_at: received).tap do |call|
      call.update_columns(status: Call.statuses[:closed], outcome: Call.outcomes[:false_alarm], dispatched_at: received + 1.minute,
                          arrived_at: received + 450.seconds, closed_at: received + 20.minutes)
    end
  end

  # Latvian writes a decimal comma, by the standard texts of the gem. Of the
  # texts of the application it is given here those that show such a number.
  before do
    I18n.backend.store_translations(:lv, language: { name: "Latviešu" }, common: { minutes: "%{count} min" },
                                         calls: { show: { arrived_after: "%{time}, %{count} min; %{response} min" },
                                                  position: { kilometres: "%{number} km" } },
                                         statistics: { false_alarms: { share: "%{share} %, %{alarms} no %{closed}" } },
                                         services: { call_step: { arrived: "Ierašanās reģistrēta; %{minutes} min" } })
    sign_in_as(dispatcher)
    call
  end

  after { I18n.backend.reload! }

  def text_of(path, asking: nil)
    get path, headers: { "HTTP_ACCEPT_LANGUAGE" => asking }
    response.parsed_body.at_css("main").text.squish
  end

  it "on the page of a call, in its response time", :aggregate_failures do
    expect(text_of(call_path(call))).to include("response time 7.5 min")
    expect(text_of(call_path(call), asking: "lv")).to include("6 min; 7,5 min")
  end

  it "in the list of calls", :aggregate_failures do
    expect(text_of(calls_path)).to include("7.5 min")
    latvian = text_of(calls_path, asking: "lv")
    expect(latvian).to include("7,5 min")
    expect(latvian).not_to include("7.5")
  end

  it "in the statistics, in an average and in a share", :aggregate_failures do
    september = statistics_path(from: "2026-09-01", to: "2026-09-30")

    expect(text_of(september)).to include("7.5 min", "100.0 %, 1 of 1 closed calls")
    latvian = text_of(september, asking: "lv")
    expect(latvian).to include("7,5 min", "100,0 %, 1 no 1")
    expect(latvian).not_to include("7.5", "100.0")
  end

  it "in what is told after an arrival", :aggregate_failures do
    active = create(:alarm_call, guarded_site: call.guarded_site, received_at: received)
    travel_to(received + 1.minute) { CallStep.new(active, dispatcher).dispatch(create(:patrol_car)) }
    told = travel_to(received + 450.seconds) { I18n.with_locale(:lv) { CallStep.new(active, dispatcher).arrive } }

    expect(told).to eq("Ierašanās reģistrēta; 7,5 min")
    expect(active.reload.response_minutes).to eq(7.5)
  end

  it "in a distance from a kilometre on", :aggregate_failures do
    helpers = ApplicationController.helpers

    expect(helpers.distance_words(1540)).to eq("1.5 km")
    expect(I18n.with_locale(:lv) { helpers.distance_words(1540) }).to eq("1,5 km")
  end

  # 4.2: the API speaks to programs; a number stays a number there.
  it "stays a number in the JSON API" do
    get api_v1_call_path(call), headers: { "Authorization" => "Bearer #{dispatcher.issue_api_key}", "HTTP_ACCEPT_LANGUAGE" => "lv" }

    expect(response.parsed_body["response_minutes"]).to eq(7.5)
  end
end
