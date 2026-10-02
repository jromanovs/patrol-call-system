class AddApiKeyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :api_key_digest, :string
    add_index :users, :api_key_digest, unique: true
    add_column :users, :api_key_issued_at, :datetime
  end
end
