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
end
