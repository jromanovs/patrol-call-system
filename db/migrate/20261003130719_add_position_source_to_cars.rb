# BR-20: the source of positions is chosen for each car instead of one switch
# for all. A car that was tracked — tracking on and an identifier issued — is
# taken as tracked by Traccar Client. The settings table with the switch
# stays: the previous version reads it until this one has taken over.
class AddPositionSourceToCars < ActiveRecord::Migration[8.1]
  def up
    add_column :patrol_cars, :position_source, :integer, null: false, default: 0
    # The positions kept so far came from Traccar Client, and so do those the
    # previous version keeps while this one is being deployed.
    add_column :car_positions, :source, :integer, null: false, default: 1
    execute <<~SQL.squish
      UPDATE patrol_cars SET position_source = 1
      WHERE tracking_key_digest IS NOT NULL AND EXISTS (SELECT 1 FROM settings WHERE car_tracking)
    SQL
  end

  def down
    remove_column :car_positions, :source
    remove_column :patrol_cars, :position_source
  end
end
