# TRK-05, BR-20: for how many months car positions are kept, the
# administrator's setting; never below 3.
class AddPositionMonthsToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :position_months, :integer, null: false, default: 24
    add_check_constraint :settings, "position_months >= 3", name: "settings_position_months"
  end
end
