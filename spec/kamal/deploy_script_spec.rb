require "rails_helper"
require "open3"
require "tmpdir"

# bin/deploy runs in a repository of its own that has no remote. In place of
# Kamal and of the GitHub client stand scripts that note what they were asked
# and answer as told: no example touches GitHub or a server.
RSpec.describe "DeployScript" do
  let(:built) { [ { status: "completed", conclusion: "success" } ] }
  let(:elsewhere) { "0123456789abcdef0123456789abcdef01234567" }
  # Stopped before Kamal was asked anything: nothing on the site has changed.
  let(:untouched) { { status: 1, kamal: [], printed: "" } }
  let(:ref) { "api repos/example/project/git/ref/heads/main --jq .object.sha" }

  # Git as a new user has it, with nothing of this machine's settings.
  def git(folder, *words)
    plain = { "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1" }
    printed, result = Open3.capture2e(plain, "git", "-C", folder, "-c", "user.name=example",
                                      "-c", "user.email=example@example.com", *words)
    raise printed unless result.success?

    printed.strip
  end

  def stand_in(file, script)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "#!/bin/sh\n#{script}")
    FileUtils.chmod("+x", file)
  end

  # Git is reached by its full path, so an example may leave the GitHub
  # client out of the search path without losing git.
  def stage(root)
    project = File.join(root, "project")
    git(root, "init", "--quiet", "--initial-branch=main", "project")
    FileUtils.mkdir_p([ File.join(project, "bin"), File.join(project, "config") ])
    FileUtils.cp(Rails.root.join("bin/deploy"), File.join(project, "bin/deploy"))
    File.write(File.join(project, "README.md"), "first\n")
    File.write(File.join(project, "config/deploy.yml"), "service: example\nimage: example/project\n")
    stand_in(File.join(project, "bin/kamal"), %(printf '%s\\n' "${PWD##*/} $*" >> "$ROOT/kamal"\nexit "${KAMAL:-0}"\n))
    stand_in(File.join(root, "path/git"), %(exec "#{`command -v git`.strip}" "$@"\n))
    git(project, "add", ".")
    git(project, "commit", "--quiet", "--message", "first")
    project
  end

  # Answers the two questions of the script: where main points, and how the
  # build of a record ended.
  def github(root)
    stand_in(File.join(root, "path/gh"), <<~SH)
      printf '%s\\n' "$*" >> "$ROOT/gh"
      echo "$NOISE" >&2
      if [ "$1" = api ]; then
        printf '%s\\n' "$MAIN"
        exit "${REF:-0}"
      fi
      printf '%s\\n' "$RUNS"
      exit "${LIST:-0}"
    SH
  end

  def asked(root, whom) = File.exist?(File.join(root, whom)) ? File.readlines(File.join(root, whom), chomp: true) : []

  def answers(root, version, runs, env)
    { "MAIN" => version, "RUNS" => runs.is_a?(String) ? runs : runs.to_json }
      .merge(env.transform_keys(&:to_s), "ROOT" => root, "PATH" => File.join(root, "path"))
  end

  # How a deploy ended, what it said, and what Kamal and GitHub were asked.
  # The block changes the staged folder before the deploy is run.
  def deploy(runs: built, words: [], client: true, **env)
    Dir.mktmpdir do |root|
      project = stage(root)
      github(root) if client
      yield project if block_given?
      version = git(project, "rev-parse", "HEAD")
      printed, message, result = Open3.capture3(answers(root, version, runs, env), RbConfig.ruby,
                                                File.join(project, "bin/deploy"), *words, chdir: root)
      { status: result.exitstatus, printed:, message:, version:, kamal: asked(root, "kamal"), github: asked(root, "gh") }
    end
  end

  it "deploys the record main points at on GitHub with the image built for it, and builds nothing", :aggregate_failures do
    outcome = deploy

    expect(outcome[:status]).to eq(0)
    expect(outcome[:message]).to be_empty
    expect(outcome[:kamal]).to eq([ "project deploy --skip-push --version=#{outcome[:version]}" ])
  end

  # The image is named as the repository, so both questions are about the
  # place the server takes the image from, whatever remotes the folder has.
  it "asks GitHub where main points and how the workflow that keeps the image ended for that record, " \
     "in the repository the image is named after", :aggregate_failures do
    outcome = deploy

    expect(outcome[:github]).to eq(
      [ ref, "run list --repo example/project --workflow image.yml --commit #{outcome[:version]} --event push " \
             "--json status,conclusion --limit 1" ]
    )
    expect(Rails.root.join(".github/workflows/image.yml")).to exist
  end

  it "hands on to Kamal the two words that do not change what is deployed, and ends as Kamal ends", :aggregate_failures do
    outcome = deploy(words: %w[ --skip-hooks --verbose ], KAMAL: "7")

    expect(outcome[:kamal]).to eq([ "project deploy --skip-push --version=#{outcome[:version]} --skip-hooks --verbose" ])
    expect(outcome[:status]).to eq(7)
  end

  # Kamal takes the last of two values of an option: a word after the
  # script's own would deploy another record, or build on this machine.
  [ "--version=0000000", "--no-skip-push", "-P", "--config-file=other.yml", "--destination=other", "--", "other" ].each do |word|
    it "changes nothing on the site when it is given the word #{word}", :aggregate_failures do
      outcome = deploy(words: [ "--verbose", word ])

      expect(outcome).to include(untouched)
      expect(outcome[:message]).to include("Not deployed", "takes --skip-hooks and --verbose, not #{word}.")
      expect(outcome[:github]).to be_empty
    end
  end

  { "a new file" => "new", "a changed file" => "README.md" }.each do |change, file|
    it "changes nothing on the site when the folder holds #{change} that is in no record", :aggregate_failures do
      outcome = deploy { |project| File.write(File.join(project, file), "later\n") }

      expect(outcome).to include(untouched)
      expect(outcome[:message]).to include("Not deployed", "changes that are in no record")
      expect(outcome[:github]).to be_empty
    end
  end

  it "changes nothing on the site when main on GitHub points at another record than the folder is at", :aggregate_failures do
    outcome = deploy(MAIN: elsewhere)

    expect(outcome).to include(untouched)
    expect(outcome[:message])
      .to include("Not deployed", "the folder is at record #{outcome[:version][0, 7]}", "main on GitHub points at 0123456.")
    expect(outcome[:github]).to eq([ ref ])
  end

  it "changes nothing on the site when GitHub cannot be asked where main points, and says what the client said",
     :aggregate_failures do
    outcome = deploy(MAIN: '{"message":"Not Found"}', REF: "1", NOISE: "gh: Not Found (HTTP 404)")

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "main on GitHub could not be read", "gh: Not Found (HTTP 404)")
    expect(outcome[:github]).to eq([ ref ])
  end

  [ "", '{"message":"Not Found"}' ].each do |answer|
    it "changes nothing on the site when the answer about main is no record (#{answer.inspect})", :aggregate_failures do
      outcome = deploy(MAIN: answer)

      expect(outcome).to include(untouched)
      expect(outcome[:message]).to include("Not deployed", "main on GitHub could not be read", "no record")
      expect(outcome[:github]).to eq([ ref ])
    end
  end

  it "changes nothing on the site when GitHub has not started to build the image of the record", :aggregate_failures do
    outcome = deploy(runs: [])

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "no build of the image of record #{outcome[:version][0, 7]}")
  end

  %w[ queued in_progress ].each do |status|
    it "changes nothing on the site while the build of the image is #{status}", :aggregate_failures do
      outcome = deploy(runs: [ { status:, conclusion: "" } ])

      expect(outcome).to include(untouched)
      expect(outcome[:message]).to include("Not deployed", "has not ended", "record #{outcome[:version][0, 7]}")
    end
  end

  %w[ failure cancelled ].each do |conclusion|
    it "changes nothing on the site when the build of the image ended as #{conclusion}", :aggregate_failures do
      outcome = deploy(runs: [ { status: "completed", conclusion: } ])

      expect(outcome).to include(untouched)
      expect(outcome[:message]).to include("Not deployed", "ended as #{conclusion}", "record #{outcome[:version][0, 7]}")
    end
  end

  it "changes nothing on the site when GitHub cannot be asked about the build, and says what the client said",
     :aggregate_failures do
    outcome = deploy(runs: [], LIST: "1", NOISE: "no connection")

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "GitHub could not be asked about the image", "no connection")
  end

  [ "<html>", "null", "{}" ].each do |answer|
    it "changes nothing on the site when the answer about the build is no list of builds (#{answer})", :aggregate_failures do
      outcome = deploy(runs: answer)

      expect(outcome).to include(untouched)
      expect(outcome[:message]).to include("Not deployed", "GitHub could not be asked about the image", "no list of builds")
    end
  end

  it "changes nothing on the site when the GitHub client is not installed", :aggregate_failures do
    outcome = deploy(client: false)

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "gh is not installed")
  end
end
