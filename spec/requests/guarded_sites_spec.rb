require "rails_helper"

RSpec.describe "Guarded sites" do
  include_context "without the seeded records"

  let(:jekaba) { create(:address, full_address: "Jēkaba iela 11, Rīga, LV-1050") }
  let(:brivibas) { create(:address, full_address: "Brīvības iela 100, Rīga, LV-1001") }
  let!(:north) do
    create(:guarded_site, contract_number: "C-00101", name: "Warehouse North", client_name: "Example Trade Ltd",
                          address: jekaba, site_type: :warehouse, district: :north, contract_start_date: "2026-03-01")
  end
  let!(:centre) do
    create(:guarded_site, contract_number: "C-00102", name: "Office Centre", client_name: "Sample Holding Ltd",
                          address: brivibas, site_type: :office, district: :centre, contract_start_date: "2026-01-15")
  end
  let(:fields) do
    { contract_number: "C-00103", name: "Shop East", client_name: "Test Retail Ltd", address_id: brivibas.id,
      site_type: "shop", district: "east", keyholder_phone: "+37100000003", contract_start_date: "2026-05-01" }
  end

  before { sign_in_as(create(:user)) }

  def listed(**params)
    get guarded_sites_path, params: params
    response.parsed_body.css("table.data-table tbody td[data-label='Name']").map { |cell| cell.text.strip }
  end

  describe "the list" do
    it "finds sites by contract number, name, client or address in any letter case (FLT-04)", :aggregate_failures do
      expect(listed(q: "c-00101")).to eq([ "Warehouse North" ])
      expect(listed(q: "OFFICE")).to eq([ "Office Centre" ])
      expect(listed(q: "sample")).to eq([ "Office Centre" ])
      expect(listed(q: "JĒKABA")).to eq([ "Warehouse North" ])
    end

    it "lists every site with a hint for a text shorter than 2 characters (FLT-04)", :aggregate_failures do
      expect(listed(q: "x")).to eq([ "Office Centre", "Warehouse North" ])
      expect(response.body).to include("Enter at least 2 characters")
    end

    it "combines filters with the text and shows the count (FLT-05)", :aggregate_failures do
      centre.suspended!

      expect(listed(q: "ltd", site_type: "office", district: "centre", contract_status: "suspended")).to eq([ "Office Centre" ])
      expect(response.parsed_body.at_css(".count").text).to eq("1 site")
      expect(listed(contract_status: "active")).to eq([ "Warehouse North" ])
    end

    it "sorts by every column in both directions, by name when none is given (SRT-02)", :aggregate_failures do
      centre.suspended!
      ascending = { "contract_number" => north, "name" => centre, "client_name" => north, "address" => centre,
                    "site_type" => centre, "district" => centre, "contract_status" => north,
                    "contract_start_date" => centre }.transform_values { |first| [ first, (first == north ? centre : north) ].map(&:name) }

      expect(listed).to eq(ascending["name"])
      ascending.each do |column, names|
        expect(listed(sort: column, direction: "asc", q: "ltd")).to eq(names)
        expect(listed(sort: column, direction: "desc", q: "ltd")).to eq(names.reverse)
      end
    end

    it "sorts type, district and contract status by the alphabet of their names (SRT-02)" do
      create(:guarded_site, name: "Alpha Shop", district: :east)

      expect(listed(sort: "district")).to eq([ "Office Centre", "Alpha Shop", "Warehouse North" ])
    end

    it "filters while typing: the form updates only the list and the page address (DYN-05)", :aggregate_failures do
      get guarded_sites_path
      form = response.parsed_body.at_css("form.filters")
      expect(form["data-turbo-frame"]).to eq("sites-list")
      expect(form.at_css("input[type=search]")["data-action"]).to eq("input->auto-submit#submit")
      expect(form.css("input[type=submit], button[type=submit]")).to be_empty
      expect(response.parsed_body.at_css("turbo-frame#sites-list[data-turbo-action=advance] table")).to be_present
    end

    it "answers a search with the list alone (DYN-05)", :aggregate_failures do
      get guarded_sites_path, params: { q: "office" }, headers: { "Turbo-Frame" => "sites-list" }

      expect(response.parsed_body.at_css("turbo-frame#sites-list .count").text).to eq("1 site")
      expect(response.parsed_body.at_css("header.site-header")).to be_nil
    end

    it "offers Clear to drop the search and the filters" do
      get guarded_sites_path, params: { q: "office", district: "centre" }

      expect(response.parsed_body.at_css("a.clear")["href"]).to eq(guarded_sites_path)
    end

    it "names the column in every cell (DSP-01)" do
      get guarded_sites_path

      table = response.parsed_body.at_css("table.data-table")
      headers = table.css("thead th").map { |header| header.text.strip }
      expect(table.css("tbody tr").map { |row| row.css("td").map { |cell| cell["data-label"] } }).to all(eq(headers))
    end
  end

  describe "the site page (DSP-02)" do
    it "shows every attribute, the coordinates and the call history", :aggregate_failures do
      create_list(:alarm_call, 2, guarded_site: north, alarm_type: :fire, sensor_zone: 7)
      get guarded_site_path(north)

      details = response.parsed_body.css("dl.details div").to_h { |row| [ row.at_css("dt").text, row.at_css("dd").text.squish ] }
      expect(details).to include("Contract number" => "C-00101", "Client" => "Example Trade Ltd", "Type" => "Warehouse",
                                 "District" => "North", "Contract start" => "01.03.2026")
      expect(details["Address"]).to eq("Jēkaba iela 11, Rīga, LV-1050 (56.951200, 24.104642)")
      expect(response.parsed_body.at_css(".calls-count").text).to eq("2 calls")
      expect(response.parsed_body.css("table.data-table tbody tr").size).to eq(2)
    end

    it "warns when the register marks the address deleted (BR-12)" do
      jekaba.deleted!
      get guarded_site_path(north)

      expect(response.parsed_body.at_css(".address-warning").text).to include("marks this address deleted")
    end
  end

  describe "the form" do
    it "gives every field a label and a hint (DSP-04)", :aggregate_failures do
      get new_guarded_site_path
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty

      get edit_guarded_site_path(north)
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
    end

    it "saves a site and opens its page (ADD-01)", :aggregate_failures do
      expect { post guarded_sites_path, params: { guarded_site: fields } }.to change(GuardedSite, :count).by(1)

      expect(response).to redirect_to(guarded_site_path(GuardedSite.find_by!(contract_number: "C-00103")))
      expect(flash[:notice]).to eq("Site created")
      expect(GuardedSite.last).to have_attributes(contract_status: "active", address: brivibas)
    end

    it "keeps the values and marks each wrong field (ADD-02)", :aggregate_failures do
      wrong = fields.merge(contract_number: "c-00101", name: "", keyholder_phone: "12345", address_id: "")
      expect { post guarded_sites_path, params: { guarded_site: wrong } }.not_to change(GuardedSite, :count)

      expect(response).to have_http_status(:unprocessable_content)
      errors = response.parsed_body.css(".field-error").map { |error| error["id"] }
      expect(errors).to match_array(%w[contract_number name keyholder_phone address_id].map { "guarded_site_#{_1}_error" })
      expect(response.parsed_body.at_css("#guarded_site_keyholder_phone")["value"]).to eq("12345")
    end

    it "refuses an address the register does not mark existing (BR-11)" do
      post guarded_sites_path, params: { guarded_site: fields.merge(address_id: create(:address, status: :erroneous).id) }

      expect(response.parsed_body.at_css("#guarded_site_address_id_error")&.text).to eq(
        "Address is not an existing address in the register"
      )
    end

    it "saves changes with the same checks (UPD-01)", :aggregate_failures do
      patch guarded_site_path(north), params: { guarded_site: { name: "Warehouse No. 3" } }
      expect(response).to redirect_to(guarded_site_path(north))
      expect(north.reload.name).to eq("Warehouse No. 3")

      patch guarded_site_path(north), params: { guarded_site: { keyholder_phone: "12345" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "suspends a contract, and the site is no longer offered for calls (UPD-02)", :aggregate_failures do
      patch guarded_site_path(north), params: { guarded_site: { contract_status: "suspended" } }
      expect(north.reload).to be_suspended

      get new_call_path
      expect(response.parsed_body.css("#call_guarded_site_id option").map(&:text).join).not_to include("Warehouse North")
    end
  end

  describe "deleting" do
    it "deletes a site without calls (DEL-01)", :aggregate_failures do
      expect { delete guarded_site_path(centre) }.to change(GuardedSite, :count).by(-1)

      expect(response).to redirect_to(guarded_sites_path)
      expect(flash[:notice]).to eq("Site deleted")
    end

    it "refuses a site with calls and says how many (DEL-02, BR-9)", :aggregate_failures do
      create_list(:alarm_call, 2, guarded_site: north)

      expect { delete guarded_site_path(north) }.not_to change(GuardedSite, :count)
      expect(flash[:alert]).to eq("Site has 2 calls and cannot be deleted; suspend the contract instead")
    end

    it "asks for confirmation (DEL-01)" do
      get guarded_site_path(centre)

      expect(response.parsed_body.at_css("form[action='#{guarded_site_path(centre)}']")["data-turbo-confirm"]).to be_present
    end
  end
end
