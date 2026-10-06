# USR-10: the language of the crew screen a phone was last sent from; its
# notices are worded in it until the user of the phone chooses one.
class AddLocaleToPushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :push_subscriptions, :locale, :string
    add_check_constraint :push_subscriptions, "locale IN ('en', 'lv', 'ru')", name: "push_subscriptions_locale"
  end
end
