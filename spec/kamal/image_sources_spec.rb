require "rails_helper"

# The build of the image reads only what a registry of images or of packages
# gives by name and version. It downloads nothing by hand and nothing from
# GitHub, so a build on the deploying machine passes when GitHub does not
# answer (README, "Building on the deploying machine").
RSpec.describe "ImageSources" do
  let(:dockerfile) { Rails.root.join("Dockerfile").read }
  # The instructions of the file, each on one line. Docker drops the comment
  # lines first, also those inside an instruction of several lines.
  let(:instructions) do
    dockerfile.lines.reject { |line| line.strip.start_with?("#") }.join.gsub("\\\n", " ").lines.map(&:squish).compact_blank
  end
  let(:stages) { instructions.grep(/\AFROM /).map(&:split) }
  let(:names) { stages.filter_map { |words| words[3] if words[2] == "AS" } }
  let(:node) { instructions.grep(/\AARG NODE_VERSION=/).sole.split("=").last }

  def packages = JSON.parse(Rails.root.join("package-lock.json").read).fetch("packages")

  it "takes Node.js for the stylesheet build from its official image, by the version the file names once", :aggregate_failures do
    expect(node).to match(/\A\d+\.\d+\.\d+\z/)
    expect(instructions).to include("FROM docker.io/library/node:$NODE_VERSION-slim AS node")
    expect(instructions.grep(/\ACOPY --from=node /).map { |line| line.split[2] })
      .to eq(%w[ /usr/local/bin/node /usr/local/lib/node_modules ])
  end

  it "builds with the Node.js of the line the checks run on" do
    checks = YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"), aliases: true).dig("jobs", "ci", "steps")

    expect(node.split(".").first).to eq(checks.find { |step| step["name"] == "Node" }.dig("with", "node-version").to_s)
  end

  it "gives the image that runs the gems and the application of the build stage, and no Node.js" do
    final = instructions.drop(instructions.rindex { |line| line.start_with?("FROM ") })

    expect(final.grep(/\ACOPY /)).to eq(
      [ 'COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"',
        "COPY --chown=rails:rails --from=build /rails /rails" ]
    )
  end

  it "takes every image from Docker Hub: the official library, and the reader of the file from Docker", :aggregate_failures do
    expect(stages.map { |words| words[1] } - names).to all(start_with("docker.io/library/"))
    expect(dockerfile.lines.first).to eq("# syntax=docker/dockerfile:1\n")
  end

  it "copies between the stages of the file alone, from no image named in passing" do
    expect(instructions.flat_map { |line| line.scan(/--from=(\S+)/) }.flatten.uniq - names).to be_empty
  end

  it "downloads nothing by hand: no instruction names an address or runs a program that fetches", :aggregate_failures do
    commands = instructions.grep(/\ARUN /).flat_map { |line| line.delete_prefix("RUN ").split(/&&|\|\||[;|]/) }
    programs = commands.map { |command| command.split.drop_while { |word| word.include?("=") }.first }

    expect(instructions.grep(%r{://})).to be_empty
    expect(instructions.grep(/github|ghcr\.io/i)).to be_empty
    expect(programs & %w[ curl wget git ]).to be_empty
  end

  it "takes every gem from rubygems.org", :aggregate_failures do
    lock = Rails.root.join("Gemfile.lock").read

    expect(lock.scan(/^(GIT|PATH|GEM)$/).flatten).to eq(%w[ GEM ])
    expect(lock.scan(/^  remote: (.+)$/).flatten).to eq(%w[ https://rubygems.org/ ])
  end

  it "takes every package of npm from its registry" do
    expect(packages.values.filter_map { |package| package["resolved"] }.map { |address| URI(address).host }.uniq)
      .to eq(%w[ registry.npmjs.org ])
  end

  # A script run at install may download a program. The one package that has
  # such a script finds its program for the server among the packages.
  it "runs the install script of one npm package, whose program for the server is a package of the registry", :aggregate_failures do
    expect(packages.select { |_name, package| package["hasInstallScript"] }.keys).to eq(%w[ node_modules/@parcel/watcher ])
    expect(packages).to include("node_modules/@parcel/watcher-linux-x64-glibc")
  end
end
