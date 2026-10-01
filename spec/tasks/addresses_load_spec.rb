require "rails_helper"
require "rake"

RSpec.describe "addresses:load", type: :task do
  subject(:task) { Rake::Task["addresses:load"] }

  include_context "with an empty address table"

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    task.reenable
  end

  around do |example|
    original = ENV.to_h.slice("FILE", "CITY")
    example.run
  ensure
    ENV.delete("FILE")
    ENV.delete("CITY")
    ENV.update(original)
  end

  it "loads the file for Riga and prints what it did" do
    ENV["FILE"] = file_fixture("aw_eka.csv").to_s

    expect { task.invoke }.to output("4 added, 0 updated, 0 marked deleted or erroneous, 2 skipped\n").to_stdout
  end

  it "stops with the names of the missing columns" do
    ENV["FILE"] = file_fixture("aw_eka_without_coordinates.csv").to_s

    expect { task.invoke }.to raise_error(SystemExit).and output("Missing columns: DD_N, DD_E\n").to_stderr
  end

  it "asks for the file" do
    expect { task.invoke }.to raise_error(SystemExit).and output(/FILE=/).to_stderr
  end
end
