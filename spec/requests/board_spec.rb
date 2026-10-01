require "rails_helper"

RSpec.describe "Board cars panel (DSP-03, DYN-02)" do
  include_context "without the seeded records"

  before { sign_in_as(create(:user)) }

  it "lists every car with its status, free cars first, and counts the free ones", :aggregate_failures do
    create(:patrol_car, call_sign: "P-21", status: :out_of_service)
    create(:patrol_car, call_sign: "P-15")
    create(:patrol_car, call_sign: "P-12")
    get root_path

    panel = response.parsed_body.at_css("aside.board-cars")
    expect(panel.css("li .call-sign").map(&:text)).to eq([ "P-12", "P-15", "P-21" ])
    expect(panel.css("li .status-label").map { |label| label.text.strip }).to eq([ "Available", "Available", "Out of service" ])
    expect(panel.at_css(".count").text).to eq("2 available of 3")
  end

  it "says when there are no cars" do
    get root_path

    expect(response.parsed_body.at_css("aside.board-cars").text).to include("No cars yet.")
  end
end
