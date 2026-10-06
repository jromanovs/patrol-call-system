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

  it "deletes no older position when a new one comes: that is the nightly job's (TRK-05)" do
    old = create(:car_position, patrol_car: car, recorded_at: 25.months.ago, created_at: 25.months.ago)
    post "/traccar", params: point

    expect(CarPosition.exists?(old.id)).to be(true)
  end

  describe "an SOS signal (ADD-11, BR-21)" do
    it "registers a crew's SOS at the place sent with it, and keeps the position as any other", :aggregate_failures do
      post "/traccar", params: point(alarm: "sos")

      expect([ response.status, response.body ]).to eq([ 200, "" ])
      expect(SosCall.sole).to have_attributes(raised_by: car, latitude: 56.95, longitude: 24.1, accuracy: 9, signals: 1,
                                              status: "pending", priority: "critical", registered_by: nil)
      expect(car.car_positions.size).to eq(1)
    end

    it "keeps the time the phone took the place, when the message came later" do
      post "/traccar", params: point(alarm: "sos", timestamp: (taken - 10.minutes).to_i.to_s)

      expect(SosCall.sole).to have_attributes(placed_at: taken - 10.minutes, signalled_at: Time.current)
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
      post "/traccar", params: point(alarm: "sos").except(:lat, :lon)
      post "/traccar", params: point(alarm: "sos", id: "12345678")
      post "/traccar", params: point(alarm: "lowBattery")
      post "/traccar", params: point(alarm: [ "sos" ])

      expect(SosCall.count).to eq(0)
    end

    it "is taken though the positions of that minute have used up their limit, and has a limit of its own",
       :aggregate_failures do
      30.times { post "/traccar", params: point }
      post "/traccar", params: point
      expect(response).to have_http_status(:too_many_requests)

      statuses = Array.new(11) { post("/traccar", params: point(alarm: "sos")) && response.status }
      expect(statuses.tally).to eq(200 => 10, 429 => 1)
      expect(SosCall.sole.signals).to eq(10)
    end

    it "shows the signal on the open pages of the staff at once (DYN-19)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      post "/traccar", params: point(alarm: "sos")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(:sos, "en", hash_including(target: "sos-strips", partial: "sos_calls/strips"))
    end
  end

  describe "the application log (BR-20)" do
    # What the application writes to its log while the block runs.
    def logged
      lines = StringIO.new
      extra = ActiveSupport::Logger.new(lines)
      Rails.logger.broadcast_to(extra)
      yield
      lines.string
    ensure
      Rails.logger.stop_broadcasting_to(extra)
    end

    it "names the fields of a position, but not the car's identifier", :aggregate_failures do
      written = logged { post "/traccar", params: point }

      expect(written).to include('"id" => "[FILTERED]"', '"lat" => "56.9500"')
      expect(written).not_to include(key)
    end

    it "does not carry the identifier of a position sent as JSON", :aggregate_failures do
      written = logged { post "/traccar", params: point, as: :json }

      expect(written).to include('"id" => "[FILTERED]"')
      expect(written).not_to include(key)
    end

    it "does not carry an identifier no car has: it may be a real one mistyped", :aggregate_failures do
      written = logged { post "/traccar", params: point(id: "#{key}x") }

      expect(written).to include('"id" => "[FILTERED]"')
      expect(written).not_to include(key)
    end

    it "does not carry the identifier of an SOS", :aggregate_failures do
      written = logged { post "/traccar", params: point(alarm: "sos") }

      expect(written).to include('"id" => "[FILTERED]"')
      expect(written).not_to include(key)
    end

    it "does not carry an identifier sent as a list", :aggregate_failures do
      written = logged { post "/traccar", params: point(id: [ key ]) }

      expect(written).to include('"id" => ["[FILTERED]"]')
      expect(written).not_to include(key)
    end

    it "does not carry the identifier of a request refused for being one too many", :aggregate_failures do
      30.times { post "/traccar", params: point }
      written = logged { post "/traccar", params: point }

      expect(response).to have_http_status(:too_many_requests)
      expect(written).to include('"id" => "[FILTERED]"')
      expect(written).not_to include(key)
    end

    # API-11: a query is part of the address, and the address is logged whole.
    it "masks the identifier among the parameters of a query, whose address stays as it came" do
      written = logged { get "/traccar", params: point }

      expect(written).to include('"id" => "[FILTERED]"', "id=#{key}")
    end

    # The same list of rules serves the inspection of records, where there is
    # no request to tell the receiver by.
    it "leaves the inspection of a record as it was" do
      expect(car.inspect).to include("id: #{car.id}")
    end

    it "names the record of every other request as before" do
      sign_in_as(create(:user))
      written = logged { get patrol_car_path(car) }

      expect(written).to include(%("id" => "#{car.id}"))
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
