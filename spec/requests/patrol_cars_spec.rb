require "rails_helper"

RSpec.describe "Patrol cars" do
  include_context "without the seeded records"

  let!(:octavia) { create(:patrol_car, call_sign: "P-12", plate_number: "ZZ-0012", model: "Skoda Octavia", crew_size: 2, district: :north) }
  let!(:passat) { create(:patrol_car, call_sign: "P-3", plate_number: "AA-0003", model: "VW Passat", crew_size: 3, district: :centre) }
  let(:fields) { { call_sign: "P-15", plate_number: "zz-0015", model: "Toyota Corolla", crew_size: "4", district: "east" } }

  before { sign_in_as(create(:user)) }

  def listed(**params)
    get patrol_cars_path, params: params
    response.parsed_body.css("table.data-table tbody td[data-label='Call sign']").map { |cell| cell.text.strip }
  end

  describe "the list" do
    it "searches call sign, plate and model, filters by status and district, with the count (FLT-06)", :aggregate_failures do
      passat.out_of_service!

      expect(listed(q: "passat")).to eq([ "P-3" ])
      expect(listed(q: "zz-00")).to eq([ "P-12" ])
      expect(listed(status: "available", district: "north")).to eq([ "P-12" ])
      expect(response.parsed_body.at_css(".count").text).to eq("1 car")
      expect(listed(q: "x")).to eq([ "P-12", "P-3" ])
    end

    it "sorts by every column in both directions, by call sign when none is given (SRT-03)", :aggregate_failures do
      passat.out_of_service!
      ascending = { "call_sign" => [ "P-12", "P-3" ], "plate_number" => [ "P-3", "P-12" ], "model" => [ "P-12", "P-3" ],
                    "crew_size" => [ "P-12", "P-3" ], "district" => [ "P-3", "P-12" ], "status" => [ "P-12", "P-3" ] }

      expect(listed).to eq(ascending["call_sign"])
      ascending.each do |column, signs|
        expect(listed(sort: column, direction: "asc")).to eq(signs)
        expect(listed(sort: column, direction: "desc")).to eq(signs.reverse)
      end
    end

    it "updates only the list while typing and offers Clear (FLT-06)", :aggregate_failures do
      get patrol_cars_path, params: { q: "passat" }

      expect(response.parsed_body.at_css("form.filters")["data-turbo-frame"]).to eq("cars-list")
      expect(response.parsed_body.at_css("turbo-frame#cars-list[data-turbo-action=advance] table")).to be_present
      expect(response.parsed_body.at_css("a.clear")["href"]).to eq(patrol_cars_path)
    end
  end

  describe "the car page (DSP-02)" do
    it "shows every attribute, the current call and the recent calls", :aggregate_failures do
      site = create(:guarded_site, name: "Warehouse No. 3")
      create(:alarm_call, patrol_car: octavia, guarded_site: site)
      get patrol_car_path(octavia)

      details = response.parsed_body.css("dl.details div").to_h { |row| [ row.at_css("dt").text, row.at_css("dd").text.squish ] }
      expect(details).to include("Plate number" => "ZZ-0012", "Model" => "Skoda Octavia", "Crew" => "2", "District" => "North",
                                 "Status" => "Available")
      expect(details["Current call"]).to include("Warehouse No. 3")
      expect(response.parsed_body.css("table.data-table tbody tr").size).to eq(1)
    end
  end

  describe "the form" do
    it "gives every field a label and a hint (DSP-04)", :aggregate_failures do
      get new_patrol_car_path
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty

      get edit_patrol_car_path(octavia)
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
    end

    it "saves an available car and opens its page (ADD-03)", :aggregate_failures do
      expect { post patrol_cars_path, params: { patrol_car: fields } }.to change(PatrolCar, :count).by(1)

      car = PatrolCar.find_by!(call_sign: "P-15")
      expect(response).to redirect_to(patrol_car_path(car))
      expect(flash[:notice]).to eq("Car created")
      expect(car).to have_attributes(status: "available", plate_number: "ZZ-0015")
    end

    it "refuses a crew of 5 and a taken call sign with messages at the fields (ADD-04)", :aggregate_failures do
      expect { post patrol_cars_path, params: { patrol_car: fields.merge(crew_size: "5", call_sign: "P-12") } }
        .not_to change(PatrolCar, :count)

      expect(response.parsed_body.at_css("#patrol_car_crew_size_error").text).to eq("Crew size must be between 1 and 4")
      expect(response.parsed_body.at_css("#patrol_car_call_sign_error").text).to eq("Call sign has already been taken")
    end

    it "puts a car out of service, and back (UPD-03, UPD-04)", :aggregate_failures do
      patch patrol_car_path(octavia), params: { patrol_car: { status: "out_of_service", model: "Skoda Superb" } }
      expect(response).to redirect_to(patrol_car_path(octavia))
      expect(octavia.reload).to have_attributes(status: "out_of_service", model: "Skoda Superb")

      patch patrol_car_path(octavia), params: { patrol_car: { status: "available" } }
      expect(octavia.reload).to be_available
    end

    it "refuses out of service for a car with an active call, naming the call (BR-6)", :aggregate_failures do
      create(:alarm_call, patrol_car: octavia, guarded_site: create(:guarded_site, name: "Warehouse No. 3"))
      patch patrol_car_path(octavia), params: { patrol_car: { status: "out_of_service" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.at_css("#patrol_car_status_error").text).to include("active call at Warehouse No. 3")
      expect(octavia.reload).to be_available
    end

    it "never sets dispatched or on scene by hand (BR-5)" do
      patch patrol_car_path(octavia), params: { patrol_car: { status: "dispatched" } }

      expect(octavia.reload).to be_available
    end
  end

  describe "deleting" do
    it "deletes a car without calls (DEL-03)", :aggregate_failures do
      expect { delete patrol_car_path(passat) }.to change(PatrolCar, :count).by(-1)

      expect(response).to redirect_to(patrol_cars_path)
      expect(flash[:notice]).to eq("Car deleted")
    end

    it "refuses a car with calls and suggests out of service (DEL-04, BR-9)", :aggregate_failures do
      create_list(:alarm_call, 2, patrol_car: octavia)

      expect { delete patrol_car_path(octavia) }.not_to change(PatrolCar, :count)
      expect(flash[:alert]).to eq("Car has 2 calls and cannot be deleted; put it out of service instead")
    end

    it "refuses a car whose positions are kept, and says since when (DEL-04, BR-20)", :aggregate_failures do
      create(:car_position, patrol_car: passat, created_at: Time.zone.local(2026, 10, 3, 13, 4))

      expect { delete patrol_car_path(passat) }.not_to change(CarPosition, :count)
      expect(flash[:alert])
        .to eq("Car has positions kept since 03.10.2026 and cannot be deleted; put it out of service instead")
      expect(passat.reload).to be_persisted
    end

    it "refuses a car with crew users and says to move them first (DEL-04, BR-9)", :aggregate_failures do
      car = create(:patrol_car)
      create_list(:user, 2, :crew, patrol_car: car)
      delete patrol_car_path(car)

      expect(flash[:alert]).to eq("Car has 2 crew users and cannot be deleted; move them to another car first")
      expect(car.reload).to be_persisted
    end
  end
end
