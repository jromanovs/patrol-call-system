class WidenActivePatrolCarIndex < ActiveRecord::Migration[8.1]
  def change
    # STO-03, BR-4: a car serves one active call at a time; accepted (5) is
    # active too.
    remove_index :calls, :patrol_car_id, unique: true, where: "status IN (1, 2)", name: "index_calls_on_active_patrol_car"
    add_index :calls, :patrol_car_id, unique: true, where: "status IN (1, 2, 5)", name: "index_calls_on_active_patrol_car"
  end
end
