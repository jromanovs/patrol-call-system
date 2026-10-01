FactoryBot.define do
  factory :guarded_site do
    sequence(:contract_number) { |n| format("C-%05d", n) }
    name { "Warehouse No. 3" }
    client_name { "Example Trade Ltd" }
    address
    site_type { :warehouse }
    district { :north }
    keyholder_phone { "+37100000001" }
    contract_start_date { Date.new(2026, 3, 1) }

    trait :suspended do
      contract_status { :suspended }
    end
  end
end
