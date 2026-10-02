require "rails_helper"

RSpec.describe MapBuildJob do
  def build_result(status, reason = nil) = MapBuild::Result.new(status:, file: nil, reason:)

  it "builds the map when it is due (STO-06)" do
    build = instance_double(MapBuild, call: build_result(:built))
    allow(MapBuild).to receive(:new).and_return(build)

    described_class.perform_now

    expect(build).to have_received(:call).with(force: false)
  end

  it "fails with the reason, so the failure is recorded among the failed jobs" do
    allow(MapBuild).to receive(:new).and_return(instance_double(MapBuild, call: build_result(:failed, "tilemaker failed")))

    expect { described_class.perform_now }.to raise_error(MapBuild::Failed, "tilemaker failed")
  end

  it "is planned every night at 03:00 Riga time" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "build_map")

    expect(task).to eq("class" => "MapBuildJob", "schedule" => "0 3 * * * Europe/Riga")
  end
end
