# DEL-09, BR-23: for how many months calls are kept before they can be
# deleted, the administrator's setting, 3 to 1200.
class AddCallMonthsToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :call_months, :integer, null: false, default: 24
    add_check_constraint :settings, "call_months BETWEEN 3 AND 1200", name: "settings_call_months"
  end
end
