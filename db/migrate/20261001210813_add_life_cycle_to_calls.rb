class AddLifeCycleToCalls < ActiveRecord::Migration[8.1]
  def change
    change_table :calls, bulk: true do |t|
      t.datetime :dispatched_at
      t.datetime :arrived_at
      t.datetime :closed_at
      t.integer :outcome
      t.references :dispatched_by, foreign_key: { to_table: :users }
    end
    # BR-4, STO-03: a car is never on two active calls (statuses dispatched
    # and on_scene), even when two dispatchers send it at the same moment.
    add_index :calls, :patrol_car_id, unique: true, where: "status IN (1, 2)", name: "index_calls_on_active_patrol_car"
  end
end
