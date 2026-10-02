require "rails_helper"
require "rake"

# bin/rails demo:load: the seeds, then the demo data on top of them.
RSpec.describe "demo:load", type: :task do
  include_context "without the seeded records"

  let(:task) { Rake::Task["demo:load"] }

  def capture_output
    printed = StringIO.new
    $stdout = printed
    yield
    printed.string
  ensure
    $stdout = STDOUT
  end

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:load")
    Rake::Task.tasks.each(&:reenable)
  end

  it "loads the seeds first, then prints what it added and the passwords of the new users", :aggregate_failures do
    printed = capture_output { task.invoke }

    expect(printed.lines.first).to eq("8 sites, 3 users and 150 calls added\n")
    expect(printed.lines.drop(1).map(&:split).map { |email, password| [ email, password.size ] })
      .to eq([ [ "dispatcher@example.com", 20 ], [ "supervisor@example.com", 20 ], [ "administrator@example.com", 20 ] ])
    expect([ Address.count >= 6, GuardedSite.count, PatrolCar.count ]).to eq([ true, 12, 5 ])
  end

  it "stops with the reason and loads nothing on a conflict", :aggregate_failures do
    create(:guarded_site, contract_number: "C-00017", name: "Own Site")

    expect { task.invoke }.to raise_error(SystemExit).and output(/C-00017 belongs to Own Site/).to_stderr
    expect(Call.count).to eq(0)
  end

  it "says so when everything is there already" do
    task.invoke
    Rake::Task.tasks.each(&:reenable)

    expect { task.invoke }.to output("Demo data is loaded already; nothing added\n").to_stdout
  end
end
