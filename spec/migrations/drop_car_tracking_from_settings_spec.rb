require "rails_helper"
require Rails.root.glob("db/migrate/*_drop_car_tracking_from_settings.rb").sole

RSpec.describe DropCarTrackingFromSettings do
  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }

  # A model reads its columns once: after an example that changed them it
  # reads them anew.
  after { [ Setting, CarPosition ].each(&:reset_column_information) }

  # What the database itself says of a column, or nil when it has none.
  def column(table, name)
    connection.select_one(<<~SQL.squish)
      SELECT column_default AS preset, is_nullable AS empty FROM information_schema.columns
      WHERE table_schema = current_schema() AND table_name = #{connection.quote(table)}
        AND column_name = #{connection.quote(name)}
    SQL
  end

  def run(direction) = migration.suppress_messages { migration.migrate(direction) }

  it "leaves the settings their two periods, and a position no source of its own accord", :aggregate_failures do
    expect(column("settings", "car_tracking")).to be_nil
    expect([ column("settings", "position_months"), column("settings", "call_months") ]).to all(be_present)
    expect(column("car_positions", "source")).to eq("preset" => nil, "empty" => "NO")
  end

  it "goes back to the switch for all cars, off, and to Traccar Client as the source of a position", :aggregate_failures do
    run(:down)

    expect(column("settings", "car_tracking")).to eq("preset" => "false", "empty" => "NO")
    expect(column("car_positions", "source")).to eq("preset" => "1", "empty" => "NO")
  end

  it "comes forward again from there, and the two periods stay as they were", :aggregate_failures do
    periods = -> { [ column("settings", "position_months"), column("settings", "call_months") ] }
    before = periods.call
    run(:down)
    run(:up)

    expect(column("settings", "car_tracking")).to be_nil
    expect(column("car_positions", "source")).to eq("preset" => nil, "empty" => "NO")
    expect(periods.call).to eq(before).and all(be_present)
  end
end
