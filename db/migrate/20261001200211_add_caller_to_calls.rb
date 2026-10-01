class AddCallerToCalls < ActiveRecord::Migration[8.1]
  def change
    change_table :calls, bulk: true do |t|
      t.string :caller_name
      t.string :caller_phone
    end
  end
end
