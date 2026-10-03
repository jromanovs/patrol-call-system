class CreateCarPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :car_positions do |t|
      t.references :patrol_car, null: false, foreign_key: true, index: false
      t.decimal :latitude, precision: 9, scale: 6, null: false
      t.decimal :longitude, precision: 9, scale: 6, null: false
      t.integer :accuracy
      t.datetime :recorded_at, null: false

      t.timestamps
    end
    add_index :car_positions, %i[patrol_car_id recorded_at]
    add_index :car_positions, :recorded_at
  end
end
