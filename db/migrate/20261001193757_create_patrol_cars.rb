class CreatePatrolCars < ActiveRecord::Migration[8.1]
  def change
    create_table :patrol_cars do |t|
      t.string :call_sign, null: false
      t.string :plate_number, null: false
      t.string :model, null: false
      t.integer :crew_size, null: false
      t.integer :district, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :patrol_cars, :call_sign, unique: true
    add_index :patrol_cars, :plate_number, unique: true
  end
end
