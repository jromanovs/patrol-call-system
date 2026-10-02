class AddPatrolCarToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :patrol_car, foreign_key: true
    # 2.5: a crew user (role 3) has a car, every other user none.
    add_check_constraint :users, "(role = 3) = (patrol_car_id IS NOT NULL)", name: "users_car_only_for_crew"
  end
end
