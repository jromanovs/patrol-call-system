require "rails_helper"

RSpec.describe ActiveRecord::DatabaseConfigurations do
  subject(:production) do
    yaml = ERB.new(Rails.root.join("config/database.yml").read).result
    described_class.new(YAML.safe_load(yaml, aliases: true)).configs_for(env_name: "production")
  end

  before { allow(ENV).to receive(:[]).and_call_original }

  it "connects every production database to the host named in DB_HOST" do
    allow(ENV).to receive(:[]).with("DB_HOST").and_return("patrol_call_system-db")

    expect(production.map(&:host)).to all(eq("patrol_call_system-db"))
  end
end
