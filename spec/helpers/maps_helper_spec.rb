require "rails_helper"

RSpec.describe MapsHelper do
  describe "#position_age (TRK-02, TRK-03)" do
    let(:now) { Time.zone.local(2026, 10, 3, 13, 4) }

    it "says how long ago a position came, in minutes, hours and then the date", :aggregate_failures do
      expect(helper.position_age(now - 59.seconds, now)).to eq("just now")
      expect(helper.position_age(now - 60.seconds, now)).to eq("1 min ago")
      expect(helper.position_age(now - 59.minutes, now)).to eq("59 min ago")
      expect(helper.position_age(now - 60.minutes, now)).to eq("1 h ago")
      expect(helper.position_age(now - 24.hours, now)).to eq("02.10.2026 13:04")
    end
  end
end
