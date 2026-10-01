# A call raised by the alarm system of the site (2.6).
class AlarmCall < Call
  # BR-2: the priority each alarm type starts with; the dispatcher may change it.
  PRIORITIES = { "panic" => "critical", "fire" => "critical", "intrusion" => "high", "tamper" => "normal",
                 "power_failure" => "low" }.freeze

  enum :alarm_type, { intrusion: 0, fire: 1, panic: 2, tamper: 3, power_failure: 4 }, validate: true

  validates :sensor_zone, numericality: { only_integer: true, in: 1..99, message: "must be from 1 to 99" }

  before_validation { self.priority ||= PRIORITIES[alarm_type] }
end
