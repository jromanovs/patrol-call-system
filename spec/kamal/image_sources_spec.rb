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
  let(:node) { instructions.grep(/\AARG NODE_VERSION=/).sole.split("=").last }

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

  it "leaves Node.js out of the image that runs" do
    final = instructions.rindex { |line| line.start_with?("FROM ") }

    expect(instructions.drop(final).grep(/--from=node\b/)).to be_empty
  end

  it "takes every image from the official library of Docker Hub" do
    stages = instructions.grep(/\AFROM /).map(&:split)
    images = stages.map { |words| words[1] } - stages.map(&:last)

    expect(images).to all(start_with("docker.io/library/"))
  end

  it "downloads nothing by hand: no instruction names an address", :aggregate_failures do
    expect(instructions.grep(%r{://})).to be_empty
    expect(instructions.grep(/github/i)).to be_empty
  end

  it "takes every gem from rubygems.org", :aggregate_failures do
    lock = Rails.root.join("Gemfile.lock").read

    expect(lock.scan(/^(GIT|PATH|GEM)$/).flatten).to eq(%w[ GEM ])
    expect(lock.scan(/^  remote: (.+)$/).flatten).to eq(%w[ https://rubygems.org/ ])
  end

  it "takes every package of npm from its registry" do
    packages = JSON.parse(Rails.root.join("package-lock.json").read).fetch("packages").values

    expect(packages.filter_map { |package| package["resolved"] }.map { |address| URI(address).host }.uniq)
      .to eq(%w[ registry.npmjs.org ])
  end
end
