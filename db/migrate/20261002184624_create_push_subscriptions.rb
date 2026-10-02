class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # CRW-04: a phone that receives the crew's notices, as its push service knows it.
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false, index: { unique: true }
      t.string :p256dh, null: false
      t.string :auth, null: false

      t.timestamps
    end
  end
end
