require "rails_helper"

RSpec.describe "The receiver of Traccar Client (API-11, BR-13)" do
  let(:lines) { [] }

  before do
    TraccarController::COUNTS.clear
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(/\ATraccar Client: /) { |line| lines << line }
  end

  it "answers a form posted without a sign-in and logs what came, with the app's user agent", :aggregate_failures do
    post "/traccar", params: { id: "123456", lat: "56.95", lon: "24.1", timestamp: "1790000000" },
                     headers: { "User-Agent" => "TraccarClient/10.1.2" }

    expect([ response.status, response.body ]).to eq([ 200, "" ])
    expect(lines.sole).to include("POST", "id=123456&lat=56.95&lon=24.1&timestamp=1790000000", "TraccarClient/10.1.2")
  end

  it "answers a query and a JSON body alike", :aggregate_failures do
    get "/traccar?id=1&lat=2"
    post "/traccar", params: '{"device_id":"1","location":{"coords":{"latitude":56.95}}}',
                     headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(lines.first).to include("GET", "id=1&lat=2")
    expect(lines.last).to include("POST", "application/json", '{"device_id":"1","location":{"coords":{"latitude":56.95}}}')
  end

  it "logs no more than the first 2000 characters of a body" do
    post "/traccar", params: "x" * 3000, headers: { "Content-Type" => "text/plain" }

    expect(lines.sole[/x+/].size).to eq(2000)
  end

  it "keeps nothing in the database" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { post "/traccar", params: { id: "1" } }

    expect(queries).to be_empty
  end

  it "answers more than 30 requests a minute from one address with 429" do
    statuses = Array.new(31) { post("/traccar", params: { id: "1" }) && response.status }

    expect(statuses.tally).to eq(200 => 30, 429 => 1)
  end
end
