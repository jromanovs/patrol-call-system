FactoryBot.define do
  factory :alarm_call do
    guarded_site
    registered_by factory: :user
    alarm_type { :intrusion }
    sensor_zone { 3 }
  end
end
