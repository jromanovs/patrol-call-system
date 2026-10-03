class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.boolean :car_tracking, null: false, default: false

      t.timestamps
    end
  end
end
