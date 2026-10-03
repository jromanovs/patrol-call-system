FactoryBot.define do
  factory :alarm_call do
    guarded_site
    registered_by factory: :user
    alarm_type { :intrusion }
    sensor_zone { 3 }
  end

  factory :client_call do
    guarded_site
    registered_by factory: :user
    caller_name { "Example Person" }
    caller_phone { "+37100000005" }
  end

  # A crew that asks for help: no site, the place of the signal.
  factory :sos_call do
    raised_by factory: :patrol_car
    latitude { 56.95 }
    longitude { 24.1 }
    accuracy { 12 }
    signals { 1 }
    signalled_at { Time.current }
  end
end
