require "rails_helper"
require "kamal"

# The image of the application is built by a workflow on GitHub, as a deploy
# built it: for the architecture of the server, under the name of the
# record, with the label by which Kamal knows an image of this service.
RSpec.describe "ImageWorkflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/image.yml"), aliases: true) }
  let(:job) { workflow.dig("jobs", "image") }
  let(:scripts) { job.fetch("steps").filter_map { |step| step["run"] }.join("\n") }
  let(:deploy) { Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml")) }

  # YAML reads the key "on" as true.
  def triggers = workflow["on"] || workflow[true]

  it "builds the image of every record on main, and of a pull request", :aggregate_failures do
    expect(triggers.keys).to contain_exactly("push", "pull_request")
    expect(triggers["push"]).to eq("branches" => [ "main" ])
  end

  it "builds for the architecture of the server, with the label and the file a deploy builds with", :aggregate_failures do
    expect(job["runs-on"]).to eq("ubuntu-latest")
    expect(scripts).to include("--platform linux/#{deploy.builder.arches.sole}", "--label service=#{deploy.service}", "--file Dockerfile")
  end

  it "names the image by the record it is built from, in the registry of the repository's owner", :aggregate_failures do
    expect(job["env"]).to include("IMAGE" => "ghcr.io/${{ github.repository }}", "VERSION" => "${{ github.sha }}")
    expect(scripts).to include('--tag "$IMAGE:$VERSION"')
  end

  it "keeps the image of a record on main alone: a pull request only shows that it builds", :aggregate_failures do
    keeping = job.fetch("steps").select { |step| step["run"].to_s.match?(/docker (login|push)/) }

    expect(keeping).not_to be_empty
    expect(keeping.map { |step| step["if"] }.uniq).to eq([ "github.event_name == 'push'" ])
  end

  it "may write packages in this one job, and nothing else anywhere", :aggregate_failures do
    expect(workflow["permissions"]).to eq("contents" => "read")
    expect(job["permissions"]).to eq("contents" => "read", "packages" => "write")
  end

  it "gives the key of the registry to the script as a variable, never written into it", :aggregate_failures do
    expect(scripts).not_to include("secrets.")
    expect(job.fetch("steps").filter_map { |step| step["env"] }.flat_map(&:values)).to eq([ "${{ secrets.GITHUB_TOKEN }}" ])
  end

  it "runs no step of another party but the checkout the other checks use" do
    theirs = YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"), aliases: true).dig("jobs", "ci", "steps").filter_map { |step| step["uses"] }

    expect(job.fetch("steps").filter_map { |step| step["uses"] }).to eq([ theirs.first ])
  end
end
