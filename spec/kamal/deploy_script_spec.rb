require "rails_helper"
require "open3"
require "tmpdir"

# bin/deploy runs in a repository of its own whose remote stands for GitHub.
# In place of Kamal and of the GitHub client stand scripts that note what they
# were asked and answer as told: no example touches GitHub or a server.
RSpec.describe "DeployScript" do
  let(:built) { [ { status: "completed", conclusion: "success" } ] }
  # Stopped before Kamal was asked anything: nothing on the site has changed.
  let(:untouched) { { status: 1, kamal: [], printed: "" } }

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
    git(root, "init", "--quiet", "--bare", "--initial-branch=main", "github.git")
    git(root, "init", "--quiet", "--initial-branch=main", "project")
    FileUtils.mkdir_p([ File.join(project, "bin"), File.join(project, "config") ])
    FileUtils.cp(Rails.root.join("bin/deploy"), File.join(project, "bin/deploy"))
    File.write(File.join(project, "README.md"), "first\n")
    File.write(File.join(project, "config/deploy.yml"), "service: example\nimage: example/project\n")
    stand_in(File.join(project, "bin/kamal"), %(printf '%s\\n' "${PWD##*/} $*" >> "$ROOT/kamal"\nexit "${KAMAL:-0}"\n))
    stand_in(File.join(root, "path/git"), %(exec "#{`command -v git`.strip}" "$@"\n))
    record(project, "first")
    git(project, "remote", "add", "origin", File.join(root, "github.git"))
    git(project, "push", "--quiet", "origin", "main")
    project
  end

  def github(root)
    stand_in(File.join(root, "path/gh"), <<~SH)
      printf '%s\\n' "$*" >> "$ROOT/gh"
      echo "$NOISE" >&2
      printf '%s\\n' "$RUNS"
      exit "${GH:-0}"
    SH
  end

  def record(folder, message)
    git(folder, "add", ".")
    git(folder, "commit", "--quiet", "--message", message)
  end

  def asked(root, whom) = File.exist?(File.join(root, whom)) ? File.readlines(File.join(root, whom), chomp: true) : []

  # How a deploy ended, what it said, and what Kamal and GitHub were asked.
  # The block changes the staged folders before the deploy is run.
  def deploy(runs: built, words: [], client: true, **env)
    Dir.mktmpdir do |root|
      project = stage(root)
      github(root) if client
      yield project, root if block_given?
      answer = runs.is_a?(String) ? runs : runs.to_json
      env = env.transform_keys(&:to_s).merge("ROOT" => root, "RUNS" => answer, "PATH" => File.join(root, "path"))
      printed, message, result = Open3.capture3(env, RbConfig.ruby, File.join(project, "bin/deploy"), *words, chdir: root)
      { status: result.exitstatus, printed:, message:, version: git(project, "rev-parse", "HEAD"),
        kamal: asked(root, "kamal"), github: asked(root, "gh") }
    end
  end

  it "deploys the record main points at on GitHub with the image built for it, and builds nothing", :aggregate_failures do
    outcome = deploy

    expect(outcome[:status]).to eq(0)
    expect(outcome[:message]).to be_empty
    expect(outcome[:kamal]).to eq([ "project deploy --skip-push --version=#{outcome[:version]}" ])
  end

  # The image is named as the repository, so the question is about the place
  # the server takes the image from, whatever the folder calls its remotes.
  it "asks GitHub how the workflow that keeps the image ended for that record, in the repository the image is named after",
     :aggregate_failures do
    outcome = deploy

    expect(outcome[:github]).to eq(
      [ "run list --repo example/project --workflow image.yml --commit #{outcome[:version]} --event push " \
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
      expect(outcome[:message]).to include("Not deployed", "takes --skip-hooks and --verbose", "not #{word}")
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

  it "changes nothing on the site when main on GitHub has moved on from the record of the folder", :aggregate_failures do
    outcome = deploy do |_project, root|
      git(root, "clone", "--quiet", File.join(root, "github.git"), "other")
      File.write(File.join(root, "other/README.md"), "later\n")
      record(File.join(root, "other"), "later")
      git(File.join(root, "other"), "push", "--quiet", "origin", "main")
    end

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "record #{outcome[:version][0, 7]}", "main on GitHub points at")
    expect(outcome[:github]).to be_empty
  end

  it "changes nothing on the site when the record of the folder is not on GitHub", :aggregate_failures do
    outcome = deploy do |project|
      File.write(File.join(project, "README.md"), "later\n")
      record(project, "later")
    end

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "record #{outcome[:version][0, 7]}", "main on GitHub points at")
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

  it "changes nothing on the site when GitHub cannot be asked, and says what the client said", :aggregate_failures do
    outcome = deploy(runs: [], GH: "1", NOISE: "no connection")

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "GitHub could not be asked", "no connection")
  end

  it "changes nothing on the site when GitHub answers what is no list of builds", :aggregate_failures do
    outcome = deploy(runs: "<html>")

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "GitHub could not be asked", "no list of builds")
  end

  it "changes nothing on the site when the GitHub client is not installed", :aggregate_failures do
    outcome = deploy(client: false)

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "gh is not installed")
  end

  it "changes nothing on the site when GitHub cannot be reached to read main", :aggregate_failures do
    outcome = deploy { |_project, root| FileUtils.rm_rf(File.join(root, "github.git")) }

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "main on GitHub could not be read")
    expect(outcome[:github]).to be_empty
  end

  it "changes nothing on the site when the remote of the folder has no main", :aggregate_failures do
    outcome = deploy { |_project, root| git(File.join(root, "github.git"), "update-ref", "-d", "refs/heads/main") }

    expect(outcome).to include(untouched)
    expect(outcome[:message]).to include("Not deployed", "main on GitHub could not be read", "no branch main")
    expect(outcome[:github]).to be_empty
  end
end
