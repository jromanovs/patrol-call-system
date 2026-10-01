class CreateGuardedSites < ActiveRecord::Migration[8.1]
  def change
    create_table :guarded_sites do |t|
      t.string :contract_number, null: false
      t.string :name, null: false
      t.string :client_name, null: false
      t.references :address, null: false, foreign_key: true
      t.integer :site_type, null: false
      t.integer :district, null: false
      t.string :keyholder_phone, null: false
      t.integer :contract_status, null: false, default: 0
      t.date :contract_start_date, null: false
      t.text :access_notes
      t.timestamps
    end
    add_index :guarded_sites, "lower(contract_number)", unique: true
  end
end
