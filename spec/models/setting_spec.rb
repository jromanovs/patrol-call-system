require "rails_helper"

RSpec.describe Setting do
  it "keeps one row of settings, with car tracking off at first (TRK-01)", :aggregate_failures do
    expect(described_class.current).not_to be_car_tracking
    described_class.current.update!(car_tracking: true)

    expect(described_class.current).to be_car_tracking
    expect(described_class.count).to eq(1)
  end
end
