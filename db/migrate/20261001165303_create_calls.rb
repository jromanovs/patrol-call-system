class CreateCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :calls do |t|
      t.string :type, null: false
      t.references :guarded_site, null: false, foreign_key: true
      t.references :registered_by, null: false, foreign_key: { to_table: :users }
      t.integer :priority, null: false
      t.integer :status, null: false, default: 0
      t.datetime :received_at, null: false
      t.text :description
      t.integer :alarm_type
      t.integer :sensor_zone
      t.timestamps
    end
    add_index :calls, :status
  end
end
