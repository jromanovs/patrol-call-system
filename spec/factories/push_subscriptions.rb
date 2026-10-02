FactoryBot.define do
  factory :push_subscription do
    user factory: %i[ user crew ]
    sequence(:endpoint) { |n| "https://fcm.googleapis.com/fcm/send/phone-#{n}" }
    p256dh { "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM=" }
    auth { "tBHItJI5svbpez7KI4CCXg==" }
  end
end
