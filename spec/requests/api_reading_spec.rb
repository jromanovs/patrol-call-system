require "rails_helper"

RSpec.describe "API reading (API-01, API-02, API-09)" do
  include_context "without the seeded records"

  let(:user) { create(:user) }
  # Three sites, two of them in the centre, and one car.
  let!(:records) do
    address = create(:address, full_address: "Brīvības iela 100, Rīga, LV-1001", postal_code: "LV-1001")
    create(:guarded_site, name: "Warehouse North", district: :north)
    { address:, car: create(:patrol_car, call_sign: "P-12", district: :centre),
      office: create(:guarded_site, name: "Office Centre", district: :centre, site_type: :office, address:),
      shop: create(:guarded_site, name: "Alpha Shop", district: :centre, site_type: :shop) }
  end

  %i[ address car office shop ].each { |name| define_method(name) { records.fetch(name) } }

  describe "sites" do
    it "lists the sites with the filters and the order of the site list, and their number (API-01)", :aggregate_failures do
      body = api_get(api_v1_sites_path, user:, params: { district: "centre", sort: "name", direction: "desc" })

      expect(response).to have_http_status(:ok)
      expect(body["count"]).to eq(2)
      expect(body["sites"].pluck("name")).to eq([ "Office Centre", "Alpha Shop" ])
      expect(api_get(api_v1_sites_path, user:, params: { q: "north" })["sites"].pluck("name")).to eq([ "Warehouse North" ])
    end

    it "gives one site with its address and coordinates (API-02)" do
      body = api_get(api_v1_site_path(office), user:)

      expect(body).to include("id" => office.id, "contract_number" => office.contract_number, "name" => "Office Centre",
                              "site_type" => "office", "district" => "centre", "contract_status" => "active",
                              "address" => { "code" => address.code, "full_address" => "Brīvības iela 100, Rīga, LV-1001",
                                             "postal_code" => "LV-1001", "latitude" => address.latitude.to_f,
                                             "longitude" => address.longitude.to_f, "status" => "existing" })
    end

    it "answers 404 for a site that does not exist (API-02)", :aggregate_failures do
      body = api_get(api_v1_site_path(0), user:)

      expect(response).to have_http_status(:not_found)
      expect(body).to eq("error" => "Not found")
    end
  end

  describe "patrol cars" do
    it "lists the cars with the filters of the car list and gives one car (API-01, API-02)", :aggregate_failures do
      create(:patrol_car, call_sign: "P-15", district: :north)

      expect(api_get(api_v1_patrol_cars_path, user:, params: { district: "centre" })["patrol_cars"].pluck("call_sign"))
        .to eq([ "P-12" ])
      expect(api_get(api_v1_patrol_car_path(car), user:))
        .to include("call_sign" => "P-12", "plate_number" => car.plate_number, "district" => "centre", "status" => "available")
    end
  end

  describe "calls" do
    let!(:call) do
      create(:alarm_call, guarded_site: office, alarm_type: :fire, sensor_zone: 7,
                          received_at: Time.zone.local(2026, 10, 1, 9, 0)).tap do |call|
        call.update_columns(status: Call.statuses[:closed], patrol_car_id: car.id, outcome: Call.outcomes[:false_alarm],
                            dispatched_at: call.received_at + 5.minutes, arrived_at: call.received_at + 17.minutes,
                            closed_at: call.received_at + 30.minutes)
      end
    end

    before { create(:client_call, guarded_site: shop, received_at: Time.zone.local(2026, 10, 1, 10, 0)) }

    it "lists the calls with the filters and the order of the call list (API-01)", :aggregate_failures do
      expect(api_get(api_v1_calls_path, user:)["calls"].pluck("kind")).to eq(%w[ client alarm ])
      body = api_get(api_v1_calls_path, user:, params: { status: "closed", q: "office" })
      expect([ body["count"], body["calls"].pluck("id") ]).to eq([ 1, [ call.id ] ])
    end

    it "gives one call with its site, car, steps and times in Riga time (API-02)" do
      expect(api_get(api_v1_call_path(call), user:))
        .to include("kind" => "alarm", "alarm_type" => "fire", "sensor_zone" => 7, "priority" => "critical",
                    "status" => "closed", "outcome" => "false_alarm",
                    "site" => { "id" => office.id, "name" => "Office Centre", "contract_number" => office.contract_number },
                    "car" => { "id" => car.id, "call_sign" => "P-12" },
                    "received_at" => "2026-10-01T09:00:00+03:00", "closed_at" => "2026-10-01T09:30:00+03:00",
                    "response_minutes" => 17.0, "handling_minutes" => 30)
    end

    it "refuses a period whose start is after its end (FLT-02)", :aggregate_failures do
      body = api_get(api_v1_calls_path, user:, params: { from: "2026-10-02", to: "2026-10-01" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("errors" => { "base" => [ "Period start is after period end" ] })
    end
  end

  describe "addresses" do
    it "finds up to 10 register addresses with code and coordinates (API-09)" do
      expect(api_get(api_v1_addresses_path, user:, params: { q: "brivibas 100" })["addresses"])
        .to eq([ { "code" => address.code, "full_address" => "Brīvības iela 100, Rīga, LV-1001", "postal_code" => "LV-1001",
                   "latitude" => address.latitude.to_f, "longitude" => address.longitude.to_f } ])
    end

    it "asks for 3 characters (API-09)", :aggregate_failures do
      body = api_get(api_v1_addresses_path, user:, params: { q: "br" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("error" => "Enter at least 3 characters")
    end
  end
end
