# BR-20: the source of positions is chosen for each car; the one switch for
# all cars goes. A car that was tracked — tracking on and an identifier
# issued — is taken as tracked by Traccar Client.
class AddPositionSourceToCars < ActiveRecord::Migration[8.1]
  def up
    add_column :patrol_cars, :position_source, :integer, null: false, default: 0
    # The positions kept so far all came from Traccar Client.
    add_column :car_positions, :source, :integer, null: false, default: 1
    change_column_default :car_positions, :source, from: 1, to: nil
    execute <<~SQL.squish
      UPDATE patrol_cars SET position_source = 1
      WHERE tracking_key_digest IS NOT NULL AND EXISTS (SELECT 1 FROM settings WHERE car_tracking)
    SQL
    drop_table :settings
  end

  def down
    create_table :settings do |t|
      t.boolean :car_tracking, null: false, default: false
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO settings (car_tracking, created_at, updated_at)
      SELECT EXISTS (SELECT 1 FROM patrol_cars WHERE position_source = 1), now(), now()
    SQL
    remove_column :car_positions, :source
    remove_column :patrol_cars, :position_source
  end
end
