require "rails_helper"
require "fugit"

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

  it "is planned every night at 03:00 Riga time", :aggregate_failures do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "build_map")
    after = EtOrbi.make_time(Time.zone.local(2026, 10, 2, 12, 0))

    expect(task["class"]).to eq("MapBuildJob")
    expect(Fugit.parse(task["schedule"]).next_time(after).to_t).to eq(Time.zone.local(2026, 10, 3, 3, 0))
  end
end
