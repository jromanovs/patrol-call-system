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

  it "uses the local registry and the deploy user", :aggregate_failures do
    expect(config.registry.local?).to be(true)
    expect(config.ssh.user).to eq("deploy")
  end

  it "keeps PostgreSQL 17 reachable only from the server", :aggregate_failures do
    db = config.accessory("db")
    expect(db.image).to eq("postgres:17")
    expect(db.port).to eq("127.0.0.1:5432:5432")
  end
end
