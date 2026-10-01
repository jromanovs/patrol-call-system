require "rails_helper"

RSpec.describe "db:seed", type: :task do
  before { 2.times { Rails.application.load_seed } }

  it "loads 6 register addresses and 4 sites, once however often it runs", :aggregate_failures do
    expect(Address.count).to eq(6)
    expect(Address.pluck(:full_address)).to include("Jēkaba iela 11, Rīga, LV-1050")
    expect(GuardedSite.count).to eq(4)
    expect(GuardedSite.suspended.count).to eq(1)
    expect(User.count).to eq(0)
  end

  it "loads 5 cars, one of them out of service" do
    expect(PatrolCar.group(:status).count).to eq("available" => 4, "out_of_service" => 1)
  end
end
