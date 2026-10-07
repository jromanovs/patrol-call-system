require "rails_helper"
require "kamal"

RSpec.describe Kamal::Configuration do
  subject(:config) { described_class.create_from(config_file: Rails.root.join("config/deploy.yml")) }

  # Any IPv4 address except the loopback, or an IPv6 address of four groups or more.
  let(:server_address) { /\b(?!127\.)\d{1,3}(\.\d{1,3}){3}\b|\b[0-9a-f]{1,4}(:[0-9a-f]{0,4}){3,7}\b/i }

  it "names the server by its SSH alias, never by its address", :aggregate_failures do
    expect(config.all_hosts).to eq([ "patrol-call-system" ])
    expect(Rails.root.join("config/deploy.yml").read).not_to match(server_address)
  end

  it "serves HTTPS for the public host name through kamal-proxy", :aggregate_failures do
    proxy = config.role("web").proxy
    expect(proxy.ssl?).to be(true)
    expect(proxy.hosts).to eq([ "patrol.romanov.dev" ])
  end

  it "takes the image from the container registry of GitHub, where the checks keep it, as the deploy user",
     :aggregate_failures do
    expect(config.repository).to eq("ghcr.io/jromanovs/patrol-call-system")
    expect(config.ssh.user).to eq("deploy")
  end

  # The value is never read here: reading it would ask the keychain.
  it "signs the server in to the registry as the owner of the image, with a key the keychain gives at deploy time",
     :aggregate_failures do
    registry = config.raw_config.registry

    expect(registry["username"]).to eq(config.image.split("/").first)
    expect(registry["password"]).to eq([ "KAMAL_REGISTRY_PASSWORD" ])
    expect(Rails.root.join(config.secrets_path).read).to match(
      /^KAMAL_REGISTRY_PASSWORD=\$\(security find-generic-password -s patrol-call-system -a KAMAL_REGISTRY_PASSWORD -w\)$/
    )
  end

  # The way back when GitHub cannot build or keep the image.
  it "builds on the deploying machine again with the two settings the README names", :aggregate_failures do
    section = Rails.root.join("README.md").read[/^### Building on the deploying machine\n.*?(?=^### |\z)/m].to_s
    settings = YAML.safe_load(section[/```yaml\n(.*?)```/m, 1].to_s) || {}
    back = described_class.new(YAML.safe_load_file(Rails.root.join("config/deploy.yml")).merge(settings).symbolize_keys)

    expect(settings.keys).to eq(%w[ image registry ])
    expect(back.registry.local?).to be(true)
    expect(back.repository).to eq("localhost:5555/patrol_call_system")
    expect(section).to include("bin/kamal deploy")
  end

  it "decrypts the production credentials with their own key, kept out of git and the image", :aggregate_failures do
    expect(Rails.root.join(config.secrets_path).read)
      .to match(%r{^RAILS_MASTER_KEY=\$\(cat config/credentials/production\.key\)$})
    expect(Rails.root.join("config/credentials/production.yml.enc")).to exist
    expect(Rails.root.join(".gitignore").read).to include("/config/credentials/*.key")
    expect(Rails.root.join(".dockerignore").read).to include("/config/credentials/*.key")
  end

  it "keeps the map and the crew's photos in volumes of their own, owned by the app user (STO-06, CRW-10)",
     :aggregate_failures do
    expect(config.volume_args.each_slice(2).map(&:last))
      .to eq([ "patrol_call_system_map:/rails/storage/map", "patrol_call_system_photos:/rails/storage/photos" ])
    expect(Rails.root.join("Dockerfile").read).to include("RUN mkdir -p storage/map storage/photos\n")
    expect(Rails.root.join("config/storage.yml").read).to include('root: <%= Rails.root.join("storage/photos") %>')
  end

  it "keeps PostgreSQL 17 reachable only from the server", :aggregate_failures do
    db = config.accessory("db")
    expect(db.image).to eq("postgres:17")
    expect(db.port).to eq("127.0.0.1:5432:5432")
  end
end
