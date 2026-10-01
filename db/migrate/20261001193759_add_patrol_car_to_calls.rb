class AddPatrolCarToCalls < ActiveRecord::Migration[8.1]
  def change
    add_reference :calls, :patrol_car, foreign_key: true
  end
end
