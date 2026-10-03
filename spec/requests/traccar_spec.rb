require "rails_helper"

RSpec.describe "The receiver of Traccar Client (API-11, TRK-03, BR-13, BR-20)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let!(:key) { car.issue_tracking_key }
  let(:taken) { Time.zone.local(2026, 10, 3, 13, 4) }

  # The fields the app sends, as seen in the trial; the values are made up.
  def point(**changes) = { id: key, lat: "56.9500", lon: "24.1000", timestamp: taken.to_i.to_s, accuracy: "9.4",
                           altitude: "25.1", batt: "50", charge: "false" }.merge(changes)

  before do
    travel_to(taken + 1.minute)
    TraccarController::COUNTS.clear
    Setting.current.update!(car_tracking: true)
  end

  after { travel_back }

  it "keeps a position sent without a sign-in for the car of its identifier, and moves the car on the main screens",
     :aggregate_failures do
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
    post "/traccar", params: point

    expect([ response.status, response.body ]).to eq([ 200, "" ])
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:cars)
    expect(car.car_positions.sole).to have_attributes(latitude: 56.95, longitude: 24.1, accuracy: 9, recorded_at: taken)
  end

  it "takes the same fields in a query" do
    get "/traccar", params: point

    expect(car.car_positions.size).to eq(1)
  end

  it "keeps nothing while tracking is off, and still answers 200 so the phone piles nothing up", :aggregate_failures do
    Setting.current.update!(car_tracking: false)
    post "/traccar", params: point

    expect(response).to have_http_status(:ok)
    expect(CarPosition.count).to eq(0)
  end

  it "refuses an identifier no car has, also one sent as a list", :aggregate_failures do
    post "/traccar", params: point(id: "12345678")
    expect(response).to have_http_status(:not_found)

    post "/traccar", params: point(id: [ key ])
    expect(response).to have_http_status(:not_found)

    expect(CarPosition.count).to eq(0)
  end

  it "answers a position off the earth with 200 and keeps none, as sending it again cannot mend it", :aggregate_failures do
    post "/traccar", params: point(lat: "91")

    expect(response).to have_http_status(:ok)
    expect(CarPosition.count).to eq(0)
  end

  it "takes the time of arrival for a phone's time more than 5 minutes ahead" do
    post "/traccar", params: point(timestamp: (Time.current + 6.minutes).to_i.to_s)

    expect(car.car_positions.sole.recorded_at).to eq(Time.current.change(usec: 0))
  end

  it "deletes the positions older than 30 days as new ones come" do
    old = create(:car_position, patrol_car: car, recorded_at: 31.days.ago)
    post "/traccar", params: point

    expect(CarPosition.exists?(old.id)).to be(false)
  end

  describe "more than 30 requests a minute" do
    it "are answered 429 for that identifier only, and only for that minute", :aggregate_failures do
      statuses = Array.new(31) { post("/traccar", params: point) && response.status }
      expect(statuses.tally).to eq(200 => 30, 429 => 1)

      other = create(:patrol_car).issue_tracking_key
      post "/traccar", params: point(id: other)
      expect(response).to have_http_status(:ok)

      travel(61.seconds) { post("/traccar", params: point) }
      expect(response).to have_http_status(:ok)
    end
  end
end
