FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    name { "Demo Dispatcher" }
    password { "correct-horse-battery" }

    trait :supervisor do
      role { :supervisor }
    end

    trait :administrator do
      role { :administrator }
    end
  end
end
