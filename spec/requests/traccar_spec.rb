require "rails_helper"

RSpec.describe "The receiver of Traccar Client (API-11, TRK-03, BR-13, BR-20)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12", position_source: :traccar) }
  let!(:key) { car.issue_tracking_key }
  let(:taken) { Time.zone.local(2026, 10, 3, 13, 4) }

  # The fields the app sends, as seen in the trial; the values are made up.
  def point(**changes) = { id: key, lat: "56.9500", lon: "24.1000", timestamp: taken.to_i.to_s, accuracy: "9.4",
                           altitude: "25.1", batt: "50", charge: "false" }.merge(changes)

  before do
    travel_to(taken + 1.minute)
    TraccarController::COUNTS.clear
  end

  after { travel_back }

  it "keeps a position sent without a sign-in for the car of its identifier, and moves the car on the main screens",
     :aggregate_failures do
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
    post "/traccar", params: point

    expect([ response.status, response.body ]).to eq([ 200, "" ])
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:cars)
    expect(car.car_positions.sole)
      .to have_attributes(source: "traccar", latitude: 56.95, longitude: 24.1, accuracy: 9, recorded_at: taken)
  end

  it "takes the same fields in a query" do
    get "/traccar", params: point

    expect(car.car_positions.size).to eq(1)
  end

  it "keeps nothing for a car whose source is another one, and still answers 200 so the phone piles nothing up",
     :aggregate_failures do
    statuses = %i[ not_tracked crew_phone ].map do |source|
      car.update!(position_source: source)
      post("/traccar", params: point) && response.status
    end

    expect(statuses).to eq([ 200, 200 ])
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

  describe "an SOS signal (ADD-11, BR-21)" do
    it "registers a crew's SOS at the place sent with it, and keeps the position as any other", :aggregate_failures do
      post "/traccar", params: point(alarm: "sos")

      expect([ response.status, response.body ]).to eq([ 200, "" ])
      expect(SosCall.sole).to have_attributes(raised_by: car, latitude: 56.95, longitude: 24.1, accuracy: 9, signals: 1,
                                              status: "pending", priority: "critical", registered_by: nil)
      expect(car.car_positions.size).to eq(1)
    end

    it "is taken whatever the car's position source, though the position is not kept", :aggregate_failures do
      car.update!(position_source: :not_tracked)
      post "/traccar", params: point(alarm: "sos")

      expect(response).to have_http_status(:ok)
      expect([ SosCall.count, CarPosition.count ]).to eq([ 1, 0 ])
    end

    it "counts a further signal in the same call" do
      2.times { post "/traccar", params: point(alarm: "sos") }

      expect(SosCall.sole.signals).to eq(2)
    end

    it "registers nothing off the earth, for an identifier no car has, or for another alarm word", :aggregate_failures do
      post "/traccar", params: point(alarm: "sos", lat: "91")
      post "/traccar", params: point(alarm: "sos", id: "12345678")
      post "/traccar", params: point(alarm: "lowBattery")
      post "/traccar", params: point(alarm: [ "sos" ])

      expect(SosCall.count).to eq(0)
    end

    it "shows the signal on the open pages of the staff at once (DYN-19)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      post "/traccar", params: point(alarm: "sos")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(:sos, hash_including(target: "sos-strips", partial: "sos_calls/strips"))
    end
  end

  describe "more than 30 requests a minute" do
    it "are answered 429 for that identifier only, and only for that minute", :aggregate_failures do
      statuses = Array.new(31) { post("/traccar", params: point) && response.status }
      expect(statuses.tally).to eq(200 => 30, 429 => 1)

      other = create(:patrol_car, position_source: :traccar).issue_tracking_key
      post "/traccar", params: point(id: other)
      expect(response).to have_http_status(:ok)

      travel(61.seconds) { post("/traccar", params: point) }
      expect(response).to have_http_status(:ok)
    end
  end
end
