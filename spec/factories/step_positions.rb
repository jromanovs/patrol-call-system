FactoryBot.define do
  factory :step_position do
    call factory: :alarm_call
    step { :arrival }
    user factory: %i[ user crew ]
    latitude { 56.9522 }
    longitude { 24.104642 }
    accuracy { 12 }
    distance { 111 }
  end
end
