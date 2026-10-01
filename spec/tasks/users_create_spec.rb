require "rails_helper"
require "rake"

# bin/rails users:create EMAIL=... NAME=... [ROLE=...]: the password is asked
# without echo and never printed.
RSpec.describe "users:create", type: :task do
  let(:task) { Rake::Task["users:create"] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:create")
    task.reenable
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("EMAIL").and_return("admin@example.com")
    allow(ENV).to receive(:fetch).with("NAME").and_return("Demo Administrator")
    allow($stdin).to receive_messages(tty?: true, getpass: "correct-horse-battery")
  end

  it "stops without a terminal and does not ask for the password", :aggregate_failures do
    allow($stdin).to receive(:tty?).and_return(false)

    expect { task.invoke }.to raise_error(SystemExit).and output(/terminal/).to_stderr
    expect($stdin).not_to have_received(:getpass)
  end

  it "creates the user with the typed password and never prints it", :aggregate_failures do
    expect { task.invoke }.to output(/Created admin@example\.com/).to_stdout.and change(User, :count).by(1)

    expect(User.last.authenticate("correct-horse-battery")).to be_truthy
  end

  it "gives the role named in ROLE" do
    allow(ENV).to receive(:fetch).with("ROLE", nil).and_return("administrator")

    task.invoke
    expect(User.last).to be_administrator
  end

  it "stops on a role the system does not have", :aggregate_failures do
    allow(ENV).to receive(:fetch).with("ROLE", nil).and_return("king")

    expect { task.invoke }.to raise_error(SystemExit).and output(/Unknown role king/).to_stderr
    expect(User.count).to eq(0)
  end

  it "stops when the two passwords differ", :aggregate_failures do
    allow($stdin).to receive(:getpass).and_return("correct-horse-battery", "another-password-here")

    expect { task.invoke }.to raise_error(SystemExit).and output(/do not match/).to_stderr
    expect(User.count).to eq(0)
  end
end
