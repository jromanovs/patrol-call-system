class CreateCallPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :call_photos do |t|
      t.references :call, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
