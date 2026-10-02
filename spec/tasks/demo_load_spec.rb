require "rails_helper"
require "rake"

# bin/rails demo:load: the seeds, then the demo data on top of them.
RSpec.describe "demo:load", type: :task do
  include_context "without the seeded records"

  let(:task) { Rake::Task["demo:load"] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:load")
    Rake::Task.tasks.each(&:reenable)
  end

  it "loads the seeds first, then prints what it added and the passwords of the new users", :aggregate_failures do
    expect { task.invoke }
      .to output(/8 sites, 3 users and 150 calls added.*dispatcher@example\.com \S{20}/m).to_stdout

    expect([ Address.count >= 6, GuardedSite.count, PatrolCar.count ]).to eq([ true, 12, 5 ])
  end

  it "says so when everything is there already" do
    task.invoke
    Rake::Task.tasks.each(&:reenable)

    expect { task.invoke }.to output("Demo data is loaded already; nothing added\n").to_stdout
  end
end
