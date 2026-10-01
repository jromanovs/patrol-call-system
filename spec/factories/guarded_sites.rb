FactoryBot.define do
  factory :guarded_site do
    # Far from the seeded C-00011 … C-00014: a test database made by
    # db:prepare holds the seeds.
    sequence(:contract_number, 90_001) { |n| format("C-%05d", n) }
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
