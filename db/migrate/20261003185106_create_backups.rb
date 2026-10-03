# BR-22: a further car sent to a call that has its car, with the times of its
# own steps. A car is a further car of one call at a time (BR-4), and where
# its crew's phone was at Arrived is kept with the positions of the call.
class CreateBackups < ActiveRecord::Migration[8.1]
  def change
    create_table :backups do |t|
      t.references :call, null: false, foreign_key: true
      t.references :patrol_car, null: false, foreign_key: true, index: false
      t.references :sent_by, null: false, foreign_key: { to_table: :users }
      t.datetime :sent_at, null: false
      t.datetime :accepted_at
      t.datetime :arrived_at
      t.datetime :released_at
      t.timestamps
    end
    add_index :backups, :patrol_car_id, unique: true, where: "released_at IS NULL", name: "index_backups_on_active_patrol_car"
    add_index :backups, :patrol_car_id
    add_reference :step_positions, :backup, foreign_key: true
  end
end
