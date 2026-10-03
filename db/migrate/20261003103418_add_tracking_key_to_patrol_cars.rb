class AddTrackingKeyToPatrolCars < ActiveRecord::Migration[8.1]
  def change
    add_column :patrol_cars, :tracking_key_digest, :string
    add_column :patrol_cars, :tracking_key_hint, :string
    add_column :patrol_cars, :tracking_key_issued_at, :datetime
    add_index :patrol_cars, :tracking_key_digest, unique: true
  end
end
