require "rails_helper"
require "kamal"
require "open3"
require "tmpdir"

RSpec.describe "PreDeployHook" do
  let(:hook) { Rails.root.join(".kamal/hooks/pre-deploy") }
  let(:prepared) { { network: "true", engine: "26.1.5+dfsg1", settings: '{"experimental":true,"ip6tables":true}' } }

  # What a server prints for the one read the hook makes.
  def answer(network:, engine:, settings:)
    [ ("network=#{network}" if network), "engine=#{engine}", "settings=#{settings}" ].compact.join("\n")
  end

  # The hook runs in a copy of the project's layout whose bin/kamal answers in
  # place of a server and notes what it was asked: no example touches a real one.
  def check(reply, status: 0, hosts: "example-host")
    Dir.mktmpdir do |root|
      stage(root)
      asked = File.join(root, "asked")
      env = { "KAMAL_HOSTS" => hosts, "ANSWER" => reply, "STATUS" => status.to_s, "ASKED" => asked }
      _printed, message, result = Open3.capture3(env, RbConfig.ruby, File.join(root, ".kamal/hooks/pre-deploy"))
      { status: result.exitstatus, message:, asked: File.exist?(asked) ? File.readlines(asked, chomp: true) : [] }
    end
  end

  def stage(root)
    FileUtils.mkdir_p([ File.join(root, ".kamal/hooks"), File.join(root, "bin") ])
    FileUtils.cp(hook, File.join(root, ".kamal/hooks/pre-deploy"))
    File.write(File.join(root, "bin/kamal"),
               %(#!/bin/sh\nprintf '%s\\n' "$*" >> "$ASKED"\nprintf '%s\\n' "$ANSWER"\nexit "$STATUS"\n))
    FileUtils.chmod("+x", File.join(root, "bin/kamal"))
  end

  it "lets the deploy go on to a server prepared for IPv6", :aggregate_failures do
    outcome = check(answer(**prepared))
    expect(outcome[:status]).to eq(0)
    expect(outcome[:message]).to be_empty
  end

  it "needs no settings file from Docker Engine 27 on, where the IPv6 rules are the default" do
    expect(check(answer(network: "true", engine: "27.0.1", settings: ""))[:status]).to eq(0)
  end

  it "stops the deploy when the network of the containers has no IPv6", :aggregate_failures do
    outcome = check(answer(**prepared, network: "false"))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message])
      .to include("example-host", "the network kamal has no IPv6", 'README, "Server preparation"')
  end

  it "stops the deploy before Kamal creates the network itself, without IPv6", :aggregate_failures do
    outcome = check(answer(**prepared, network: nil))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("there is no network kamal")
  end

  it "stops the deploy when an engine older than 27 has no IPv6 rules switched on", :aggregate_failures do
    outcome = check(answer(**prepared, settings: ""))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("Docker does not add its IPv6 rules")
  end

  it "stops the deploy when the settings switch the IPv6 rules off on a newer engine", :aggregate_failures do
    outcome = check(answer(network: "true", engine: "28.0.0", settings: '{"ip6tables":false}'))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("Docker does not add its IPv6 rules")
  end

  it "stops the deploy when Docker's settings are not valid JSON", :aggregate_failures do
    outcome = check(answer(**prepared, settings: "{broken"))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("its Docker settings could not be read")
  end

  it "stops the deploy when the server cannot be read, and names the way past the check", :aggregate_failures do
    outcome = check("", status: 1)
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("example-host", "it could not be read", "--skip-hooks")
  end

  it "reads every server of the deploy, and only reads", :aggregate_failures do
    asked = check(answer(**prepared), hosts: "one,two")[:asked]
    expect(asked.map { |line| line[/\Aserver exec --raw --hosts=(\S+) /, 1] }).to eq(%w[one two])
    expect(asked.first.scan(/docker (network \w+|\w+)/).flatten).to eq([ "network inspect", "version" ])
  end

  it "names every server that is not prepared", :aggregate_failures do
    outcome = check(answer(**prepared, network: "false"), hosts: "one,two")
    expect(outcome[:message]).to include("one is not prepared", "two is not prepared")
  end

  it "points at a section the README has" do
    expect(Rails.root.join("README.md").read).to include("\n### Server preparation\n")
  end

  it "is the executable file Kamal runs before a deploy", :aggregate_failures do
    config = Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml"))
    expect(hook).to eq(Rails.root.join(config.hooks_path, "pre-deploy"))
    expect(hook).to be_executable
  end
end
