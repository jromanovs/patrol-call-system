FactoryBot.define do
  factory :push_subscription do
    transient do
      user { association(:user, :crew, strategy: :create) }
    end

    # The sign-in of the user on the phone.
    session { user.sessions.create! }
    sequence(:endpoint) { |n| "https://fcm.googleapis.com/fcm/send/phone-#{n}" }
    # A P-256 public key and a 16-byte secret, as a browser gives them.
    p256dh { "BJA-ASKgnz7Tc9fjAtRcHgoLxY_4PoTzJRRoy5d7oL-wUGj-tIBVAOARalAcG1eBO39yrcSeYW1JtuFOWdgDg5c" }
    auth { "1ffQLSTcbgN38YNDstaf7w" }
  end
end
