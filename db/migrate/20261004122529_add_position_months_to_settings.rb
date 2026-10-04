# TRK-05, BR-20: for how many months car positions are kept, the
# administrator's setting, 3 to 1200; and there is one setting, whoever asks
# for it first.
class AddPositionMonthsToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :position_months, :integer, null: false, default: 24
    add_check_constraint :settings, "position_months BETWEEN 3 AND 1200", name: "settings_position_months"
    add_index :settings, "(true)", unique: true, name: "settings_one_row"
  end
end
