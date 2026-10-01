class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :name, null: false
      t.integer :role, null: false, default: 0
      t.string :google_uid
      t.boolean :active, null: false, default: true
      t.datetime :last_signed_in_at
    end
    add_index :users, :google_uid, unique: true
  end
end
