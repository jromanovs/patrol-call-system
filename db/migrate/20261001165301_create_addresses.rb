class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses do |t|
      t.integer :code, null: false
      t.string :full_address, null: false
      t.string :postal_code
      t.decimal :latitude, precision: 8, scale: 6, null: false
      t.decimal :longitude, precision: 8, scale: 6, null: false
      t.integer :status, null: false, default: 0
      t.date :register_updated_on, null: false
      t.timestamps
    end
    add_index :addresses, :code, unique: true
  end
end
