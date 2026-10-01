require "rails_helper"

RSpec.describe AddressRegisterLoad do
  include_context "without the seeded records"

  def load(name, city: "Rīga")
    described_class.new(file_fixture(name), city:).call.to_s
  end

  it "adds the addresses of the city and skips new ones without coordinates (ADD-09, ADD-10)", :aggregate_failures do
    expect(load("aw_eka.csv")).to eq("4 added, 0 updated, 0 marked deleted or erroneous, 2 skipped")

    expect(Address.order(:code).pluck(:code, :full_address, :postal_code, :status)).to eq([
      [ 101_109_572, "Brīvības iela 100, Rīga, LV-1001", "LV-1001", "existing" ],
      [ 101_126_201, "Brīvības iela 101, Rīga, LV-1001", "LV-1001", "existing" ],
      [ 101_128_182, "Brīvības gatve 214, Rīga, LV-1039", "LV-1039", "existing" ],
      [ 101_838_146, "Jēkaba iela 11, Rīga, LV-1050", "LV-1050", "existing" ]
    ])
    expect(Address.find_by(code: 101_838_146)).to have_attributes(latitude: BigDecimal("56.9512"),
                                                                  longitude: BigDecimal("24.104642"),
                                                                  register_updated_on: Date.new(2003, 1, 10))
  end

  it "changes nothing when the same file is loaded again" do
    load("aw_eka.csv")

    expect { expect(load("aw_eka.csv")).to eq("0 added, 0 updated, 0 marked deleted or erroneous, 2 skipped") }
      .not_to(change { Address.maximum(:updated_at) })
  end

  it "follows the register for known addresses, keeping the coordinates of a deleted one", :aggregate_failures do
    load("aw_eka.csv")

    expect(load("aw_eka_changed.csv")).to eq("0 added, 1 updated, 1 marked deleted or erroneous, 2 skipped")
    expect(Address.find_by(code: 101_838_146)).to have_attributes(status: "deleted", latitude: BigDecimal("56.9512"))
    expect(Address.find_by(code: 101_109_572).postal_code).to eq("LV-1011")
  end

  it "never takes the address away from a site (BR-12)", :aggregate_failures do
    load("aw_eka.csv")
    site = create(:guarded_site, address: Address.find_by(code: 101_838_146))

    load("aw_eka_changed.csv")
    expect(site.reload.address.status).to eq("deleted")
    expect(site).to be_valid
  end

  it "loads only the city that is asked for" do
    expect(load("aw_eka.csv", city: "Valmieras nov.")).to eq("1 added, 0 updated, 0 marked deleted or erroneous, 0 skipped")
  end

  it "stops before any change when columns are missing (ADD-10)", :aggregate_failures do
    expect { load("aw_eka_without_coordinates.csv") }
      .to raise_error(AddressRegisterLoad::MissingColumns, "Missing columns: DD_N, DD_E")
    expect(Address.count).to eq(0)
  end
end
