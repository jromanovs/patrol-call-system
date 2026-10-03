class CreateStepPositions < ActiveRecord::Migration[8.1]
  def change
    # CRW-07, BR-18: where the crew's phone was at its arrival and closing.
    create_table :step_positions do |t|
      t.references :call, null: false, foreign_key: true
      t.integer :step, null: false
      t.references :user, null: false, foreign_key: true
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      t.integer :accuracy
      t.integer :distance

      t.timestamps
    end
  end
end
