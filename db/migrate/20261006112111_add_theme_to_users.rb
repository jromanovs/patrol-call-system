# USR-09: how the pages look for the user: as the device asks (0), light (1)
# or dark (2).
class AddThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :theme, :integer, null: false, default: 0
    add_check_constraint :users, "theme IN (0, 1, 2)", name: "users_theme"
  end
end
