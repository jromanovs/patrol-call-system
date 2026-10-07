require "rails_helper"
require "kamal"

# A workflow on GitHub builds the image of the application as a deploy builds
# it: for the architecture of the server, from the same file, with the label
# by which Kamal knows an image of this service, under the name of the record.
RSpec.describe "ImageWorkflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/image.yml"), aliases: true) }
  let(:job) { workflow.dig("jobs", "image") }
  let(:scripts) { job.fetch("steps").filter_map { |step| step["run"] }.join("\n") }
  let(:deploy) { Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml")) }

  # YAML reads the key "on" as true.
  def triggers = workflow["on"] || workflow[true]

  # The parts of the build command, each option with its value.
  def options = scripts[/docker buildx build.*?(?=\n\S|\z)/m].gsub("\\\n", " ").scan(/--[a-z-]+(?: (?:"[^"]*"|\S+))?/).map(&:squish)

  it "runs after every push to main, and for a pull request", :aggregate_failures do
    expect(triggers.keys).to contain_exactly("push", "pull_request")
    expect(triggers["push"]).to eq("branches" => [ "main" ])
  end

  # Two merges one after the other: the image of the first is as much needed
  # as that of the second. An older run of a pull request is of no use.
  it "lets the run of a record on main end, and stops the older run of a pull request", :aggregate_failures do
    expect(workflow["concurrency"]).to eq(
      "group" => "${{ github.workflow }}-${{ github.event_name == 'push' && github.sha || github.ref }}",
      "cancel-in-progress" => "${{ github.event_name == 'pull_request' }}"
    )
  end

  it "builds as a deploy does: for the architecture of the server, from its file, in its folder, with its label", :aggregate_failures do
    builder = deploy.builder

    expect(job["runs-on"]).to eq("ubuntu-latest")
    expect(options).to include("--platform linux/#{builder.arches.sole}", "--label service=#{deploy.service}", "--file #{builder.dockerfile}")
    expect(scripts).to match(/--load #{Regexp.escape(builder.context)}$/)
    # What a deploy would add to its build and this one has not.
    expect([ builder.args, builder.secrets, builder.target ]).to all(be_blank)
  end

  it "names the image by the record it is built from, in the registry of the repository's owner, and by no other name",
     :aggregate_failures do
    expect(job["env"]).to eq("IMAGE" => "ghcr.io/${{ github.repository }}", "VERSION" => "${{ github.sha }}")
    expect(options.grep(/\A--tag/)).to eq([ '--tag "$IMAGE:$VERSION"' ])
    # No name by the short form of the option, and one push.
    expect(scripts).not_to match(/\s-t\s/)
    expect(scripts.scan(/docker push.*/)).to eq([ 'docker push "$IMAGE:$VERSION"' ])
  end

  it "keeps the image under the name by which a deploy of that record asks for it" do
    deploy.version = job["env"]["VERSION"]
    kept = job["env"].values_at("IMAGE", "VERSION").join(":")

    expect(kept.sub("${{ github.repository }}", deploy.image)).to eq(deploy.absolute_image)
  end

  it "keeps the image after a push to main alone: a pull request only shows that it builds", :aggregate_failures do
    keeping = job.fetch("steps").select { |step| step["run"].to_s.match?(/docker (login|push)/) }

    expect(keeping.size).to eq(2)
    expect(keeping.map { |step| step["if"] }.uniq).to eq([ "github.event_name == 'push'" ])
  end

  it "has one job, the only one that may write packages", :aggregate_failures do
    expect(workflow["jobs"].keys).to eq(%w[ image ])
    expect(workflow["permissions"]).to eq("contents" => "read")
    expect(job["permissions"]).to eq("contents" => "read", "packages" => "write")
  end

  it "gives the key of the registry to one script as a variable, and writes nothing of GitHub into a script", :aggregate_failures do
    expect(scripts).not_to include("${{")
    expect(job.fetch("steps").filter_map { |step| step["env"] }).to eq([ { "TOKEN" => "${{ secrets.GITHUB_TOKEN }}" } ])
  end

  # The secrets of the deployment stay on the deploying machine.
  it "is, like every workflow, given no secret but the key GitHub makes for the run", :aggregate_failures do
    texts = Rails.root.glob(".github/workflows/*.yml").map(&:read)

    expect(texts.flat_map { |text| text.scan(/secrets\.(\w+)/) }.flatten.uniq).to eq(%w[ GITHUB_TOKEN ])
    expect(texts.join).not_to match(/secrets:\s*inherit/)
  end

  it "runs no step of another party but the checkout the other checks use, and leaves no key of it behind", :aggregate_failures do
    theirs = YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"), aliases: true).dig("jobs", "ci", "steps").filter_map { |step| step["uses"] }
    checkout = job.fetch("steps").select { |step| step["uses"] }

    expect(checkout.pluck("uses")).to eq([ theirs.first ])
    expect(checkout.sole["with"]).to eq("persist-credentials" => false)
  end
end
