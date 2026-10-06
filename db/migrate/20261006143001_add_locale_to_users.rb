# USR-10: the language the user chose for the pages; none until they choose.
class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string
    add_check_constraint :users, "locale IN ('en', 'lv', 'ru')", name: "users_locale"
  end
end
