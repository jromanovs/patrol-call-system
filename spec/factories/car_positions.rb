FactoryBot.define do
  factory :car_position do
    patrol_car
    latitude { 56.9496 }
    longitude { 24.1052 }
    accuracy { 9 }
    recorded_at { Time.current }
  end
end
