FactoryBot.define do
  factory :address do
    sequence(:code) { |n| 900_000_000 + n }
    full_address { "Jēkaba iela 11, Rīga, LV-1050" }
    postal_code { "LV-1050" }
    latitude { 56.9512 }
    longitude { 24.104642 }
    register_updated_on { Date.new(2003, 1, 10) }
  end
end
