require "rails_helper"
require "kamal"
require "open3"
require "tmpdir"

RSpec.describe "PreDeployHook" do
  let(:hook) { Rails.root.join(".kamal/hooks/pre-deploy") }
  let(:prepared) do
    { network: "true", engine: "26.1.5+dfsg1", experimental: "true", settings: '{"experimental":true,"ip6tables":true}' }
  end
  # The one command the hook may run on a server: four reads, nothing else.
  let(:read) do
    [ "docker network inspect kamal --format 'network={{.EnableIPv6}}'",
      "docker version --format 'engine={{.Server.Version}} experimental={{.Server.Experimental}}'",
      %q(printf 'settings=%s\n' "$(cat /etc/docker/daemon.json 2>/dev/null | tr -d '[:space:]')"),
      "[ ! -e /etc/docker/daemon.json ] || [ -r /etc/docker/daemon.json ] || echo settings=unreadable" ].join("; ")
  end

  # What a server prints for that command.
  def answer(network:, engine:, experimental:, settings:)
    [ ("network=#{network}" if network), ("engine=#{engine} experimental=#{experimental}" if engine),
      "settings=#{settings}" ].compact.join("\n")
  end

  # The hook runs in a copy of the project's layout whose bin/kamal answers in
  # place of the servers and notes what it was asked: no example touches a real
  # one. A reply is one answer for every server or an answer for each by name.
  def check(reply, status: 0, hosts: "example-host", **env)
    Dir.mktmpdir do |root|
      stage(root, reply.is_a?(Hash) ? reply : { "any" => reply })
      env = env.transform_keys(&:to_s).merge("KAMAL_HOSTS" => hosts, "ROOT" => root, "STATUS" => status.to_s)
      printed, message, result = Open3.capture3(env, RbConfig.ruby, File.join(root, ".kamal/hooks/pre-deploy"))
      asked = File.join(root, "asked")
      { status: result.exitstatus, printed:, message:, asked: File.exist?(asked) ? File.readlines(asked, chomp: true) : [] }
    end
  end

  def stage(root, replies)
    FileUtils.mkdir_p([ File.join(root, ".kamal/hooks"), File.join(root, "bin"), File.join(root, "answers") ])
    FileUtils.cp(hook, File.join(root, ".kamal/hooks/pre-deploy"))
    replies.each { |host, reply| File.write(File.join(root, "answers", host), "#{reply}\n") }
    File.write(File.join(root, "bin/kamal"), <<~SH)
      #!/bin/sh
      printf '%s\\n' "$*" >> "$ROOT/asked"
      echo "$NOISE" >&2
      host=${4#--hosts=}
      [ -f "$ROOT/answers/$host" ] || host=any
      cat "$ROOT/answers/$host"
      exit "$STATUS"
    SH
    FileUtils.chmod("+x", File.join(root, "bin/kamal"))
  end

  it "lets the deploy go on to a server prepared for IPv6 and prints nothing", :aggregate_failures do
    outcome = check(answer(**prepared))
    expect(outcome[:status]).to eq(0)
    expect(outcome[:message]).to be_empty
    expect(outcome[:printed]).to be_empty
  end

  it "needs no settings file from Docker Engine 27 on, where the IPv6 rules are the default" do
    reply = answer(network: "true", engine: "27.0.1", experimental: "false", settings: "")
    expect(check(reply)[:status]).to eq(0)
  end

  it "takes settings that do not name the IPv6 rules as the default of the engine", :aggregate_failures do
    settings = '{"log-driver":"journald"}'
    expect(check(answer(**prepared, engine: "27.0.1", settings:))[:status]).to eq(0)
    expect(check(answer(**prepared, settings:))[:message]).to include("Docker does not add its IPv6 rules")
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

  it "stops the deploy when an older engine runs without the settings that switch the rules on", :aggregate_failures do
    outcome = check(answer(**prepared, experimental: "false"))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("Docker does not add its IPv6 rules")
  end

  it "stops the deploy when the settings switch the IPv6 rules off on a newer engine", :aggregate_failures do
    outcome = check(answer(**prepared, engine: "28.0.0", settings: '{"ip6tables":false}'))
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("Docker does not add its IPv6 rules")
  end

  [ "{broken", "[]", "unreadable" ].each do |settings|
    it "stops the deploy when Docker's settings read #{settings}", :aggregate_failures do
      outcome = check(answer(**prepared, settings:))
      expect(outcome[:status]).to eq(1)
      expect(outcome[:message]).to include("its Docker settings could not be read")
    end
  end

  # Without an engine to ask, the Docker client prints the label with no value.
  [ "settings=", "engine=\nsettings=" ].each do |reply|
    it "stops the deploy when Docker does not answer on the server (#{reply.inspect})", :aggregate_failures do
      outcome = check(reply)
      expect(outcome[:status]).to eq(1)
      expect(outcome[:message]).to include("Docker does not answer")
    end
  end

  it "stops the deploy when the server cannot be read, and names the way past the check", :aggregate_failures do
    outcome = check("", status: 1, NOISE: "kept-apart")
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("example-host", "it could not be read", "--skip-hooks")
    expect(outcome[:message] + outcome[:printed]).not_to include("kept-apart")
  end

  [ "", nil ].each do |hosts|
    it "stops the deploy when no server is named (KAMAL_HOSTS #{hosts.inspect})", :aggregate_failures do
      outcome = check(answer(**prepared), hosts:)
      expect(outcome[:status]).to eq(1)
      expect(outcome[:message]).to include("no server is named")
      expect(outcome[:asked]).to be_empty
    end
  end

  it "asks every server of the deploy the same reads and nothing else" do
    asked = check(answer(**prepared), hosts: "one,two")[:asked]
    expect(asked).to eq(%w[one two].map { |host| "server exec --raw --hosts=#{host} #{read}" })
  end

  it "names the servers that are not prepared, and only them", :aggregate_failures do
    outcome = check({ "one" => answer(**prepared), "two" => answer(**prepared, network: "false") }, hosts: "one,two")
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message]).to include("two is not prepared")
    expect(outcome[:message]).not_to include("one is not prepared")
  end

  it "prints nothing of its environment, nor of what Kamal says beside the answers", :aggregate_failures do
    reply = "#{answer(**prepared, network: 'false')}\nsecret=kept-apart"
    outcome = check(reply, RAILS_MASTER_KEY: "kept-apart", NOISE: "kept-apart")
    expect(outcome[:status]).to eq(1)
    expect(outcome[:message] + outcome[:printed]).not_to include("kept-apart")
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
