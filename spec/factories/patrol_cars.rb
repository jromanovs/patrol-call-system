FactoryBot.define do
  factory :patrol_car do
    # Apart from the seeded P-… call signs and ZZ-… plates.
    sequence(:call_sign) { |n| "T-#{n}" }
    sequence(:plate_number) { |n| "TT-#{n}" }
    model { "Skoda Octavia" }
    crew_size { 2 }
    district { :centre }
  end
end
