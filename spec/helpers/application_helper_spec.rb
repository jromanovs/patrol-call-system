require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#initials (4.3)" do
    it "takes the first letters of the first two words, in capitals", :aggregate_failures do
      expect(helper.initials("Demo Dispatcher")).to eq("DD")
      expect(helper.initials("demo crew of the north")).to eq("DC")
      expect(helper.initials("ātrā ķēde")).to eq("ĀĶ")
    end

    it "takes one letter of a name of one word" do
      expect(helper.initials("Supervisor")).to eq("S")
    end

    it "counts a hyphen, a dot, an underscore and @ as the end of a word", :aggregate_failures do
      expect(helper.initials("Night-Shift")).to eq("NS")
      expect(helper.initials("demo.crew@example.com")).to eq("DC")
      expect(helper.initials("  night_shift  ")).to eq("NS")
    end

    it "gives nothing for no name" do
      expect(helper.initials(nil)).to eq("")
    end
  end
end
