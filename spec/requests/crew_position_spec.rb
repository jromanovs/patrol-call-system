require "rails_helper"

RSpec.describe "The crew's phone as the position source (TRK-04, BR-20)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-07", position_source: :crew_phone) }
  let(:crew) { create(:user, :crew, patrol_car: car) }
  let(:place) { { latitude: 56.95, longitude: 24.1, accuracy: 9.4 } }

  def page = response.parsed_body

  before { CrewPositionsController::COUNTS.clear }

  describe "sent by the crew screen" do
    before { sign_in_as(crew) }

    it "is kept for the crew's car with its source and the time it came, and moves the car on the main screens",
       :aggregate_failures do
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      travel_to(Time.zone.local(2026, 10, 3, 12, 4)) { post crew_position_path, params: place, as: :json }

      expect(response).to have_http_status(:no_content)
      expect(car.car_positions.sole).to have_attributes(source: "crew_phone", latitude: 56.95, longitude: 24.1, accuracy: 9,
                                                        recorded_at: Time.zone.local(2026, 10, 3, 12, 4))
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(:cars)
    end

    it "is not kept when the car's source is another one, and the screen is told to stop", :aggregate_failures do
      car.update!(position_source: :traccar)
      post crew_position_path, params: place, as: :json

      expect(response).to have_http_status(:conflict)
      expect(CarPosition.count).to eq(0)
    end

    it "is refused off the earth", :aggregate_failures do
      post crew_position_path, params: place.merge(latitude: 91), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(CarPosition.count).to eq(0)
    end

    it "is answered 429 beyond 10 a minute from one user" do
      statuses = Array.new(11) { post(crew_position_path, params: place, as: :json) && response.status }

      expect(statuses.tally).to eq(204 => 10, 429 => 1)
    end
  end

  it "is the crew's only" do
    sign_in_as(create(:user))
    post crew_position_path, params: place, as: :json

    expect(CarPosition.count).to eq(0)
  end

  describe "on the crew screen" do
    before { sign_in_as(crew) }

    it "says that this phone sends the car's position, every 30 seconds while the screen is open", :aggregate_failures do
      get crew_path

      block = page.at_css("#crew-position")
      expect(block.to_h.values_at("data-controller", "data-beacon-url-value", "data-beacon-interval-value"))
        .to eq([ "beacon", crew_position_path, "30000" ])
      expect(block.key?("data-turbo-permanent")).to be(true)
      expect(block.at_css("[data-beacon-target=on]").text.squish)
        .to start_with("This phone sends the car's position Every 30 seconds while this screen is open. Last sent")
      expect(block.at_css("[data-beacon-target=off]").text.squish)
        .to eq("The phone gives no position Allow location for this app in the phone's settings.")
      expect(block.css("[data-beacon-target=on][hidden], [data-beacon-target=off][hidden]").size).to eq(2)
    end

    it "says nothing of positions for a car with another source" do
      car.update!(position_source: :traccar)
      get crew_path

      expect(page.at_css("#crew-position")).to be_nil
    end
  end
end
