require "rails_helper"

# SRT-01 … SRT-03: a column of an enumeration is sorted by the names of its
# values, and a name is of the language of the page (USR-10).
RSpec.describe "Sorting by the name of a value" do
  include_context "without the seeded records"

  def in_latvian(&) = I18n.with_locale(:lv, &)

  it "orders the cars by the names of their statuses in the language in use", :aggregate_failures do
    %w[ available dispatched on_scene out_of_service ].each { |status| create(:patrol_car).update_column(:status, PatrolCar.statuses[status]) }

    # Available, Dispatched, On scene, Out of service; Brīva, Nav dienestā, Nosūtīta, Uz vietas.
    expect(PatrolCar.list(sort: "status").map(&:status)).to eq(%w[ available dispatched on_scene out_of_service ])
    expect(in_latvian { PatrolCar.list(sort: "status").map(&:status) }).to eq(%w[ available out_of_service dispatched on_scene ])
    expect(in_latvian { PatrolCar.list(sort: "status", direction: "desc").map(&:status) })
      .to eq(%w[ on_scene dispatched out_of_service available ])
  end

  it "orders the sites by the names of their districts in the language in use", :aggregate_failures do
    %w[ centre north south east west ].each { |district| create(:guarded_site, district:) }

    # Centre, East, North, South, West; Austrumi, Centrs, Dienvidi, Rietumi, Ziemeļi.
    expect(GuardedSite.list(sort: "district").map(&:district)).to eq(%w[ centre east north south west ])
    expect(in_latvian { GuardedSite.list(sort: "district").map(&:district) }).to eq(%w[ east centre south west north ])
  end

  it "orders the calls by the names of their statuses in the language of the page", :aggregate_failures do
    calls = %w[ pending cancelled closed ].index_with { |status| create(:alarm_call).tap { |call| call.update_column(:status, Call.statuses[status]) } }
    sign_in_as(create(:user))
    listed = lambda do |asking|
      get calls_path(sort: "status"), headers: { "HTTP_ACCEPT_LANGUAGE" => asking }
      response.parsed_body.css("table tbody a[href^='/calls/']").map { |link| link["href"][%r{\A/calls/(\d+)\z}, 1] }.compact.uniq.map(&:to_i)
    end

    # Cancelled, Closed, Pending; Atcelts, Gaida, Slēgts.
    expect(listed.call("en")).to eq(calls.values_at("cancelled", "closed", "pending").map(&:id))
    expect(listed.call("lv")).to eq(calls.values_at("cancelled", "pending", "closed").map(&:id))
  end

  it "orders the calls by the names of their kinds in the language in use", :aggregate_failures do
    kinds = { "alarm" => create(:alarm_call), "client" => create(:client_call), "sos" => create(:sos_call) }.transform_values(&:id)
    listed = -> { CallFilter.new(sort: "type").results.map(&:id) }

    # Alarm, Client call, Crew's SOS; Klienta izsaukums, Mobilās grupas SOS, Trauksme.
    expect(listed.call).to eq(kinds.values_at("alarm", "client", "sos"))
    expect(in_latvian { listed.call }).to eq(kinds.values_at("client", "sos", "alarm"))
  end
end
