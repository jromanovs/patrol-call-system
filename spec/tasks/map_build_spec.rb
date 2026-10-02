require "rails_helper"
require "rake"

# bin/rails map:build: the map now, whatever its age.
RSpec.describe "map:build", type: :task do
  let(:task) { Rake::Task["map:build"] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("map:build")
    task.reenable
  end

  it "builds the map at once and prints the file" do
    build = instance_double(MapBuild, call: MapBuild::Result.new(status: :built, file: "latvia-2026-10-02T000000Z.pmtiles", reason: nil))
    allow(MapBuild).to receive(:new).and_return(build)

    expect { task.invoke }.to output("Map built: latvia-2026-10-02T000000Z.pmtiles\n").to_stdout
    expect(build).to have_received(:call).with(force: true)
  end

  it "stops with the reason when the build fails" do
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, call: MapBuild::Result.new(status: :failed, file: nil, reason: "tilemaker failed")))

    expect { task.invoke }.to raise_error(SystemExit).and output("Map not built: tilemaker failed\n").to_stderr
  end
end
