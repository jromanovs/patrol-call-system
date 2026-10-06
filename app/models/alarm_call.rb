# A call raised by the alarm system of the site (2.6).
class AlarmCall < Call
  # BR-2: the priority each alarm type starts with; the dispatcher may change it.
  PRIORITIES = { "panic" => "critical", "fire" => "critical", "intrusion" => "high", "tamper" => "normal",
                 "power_failure" => "low" }.freeze

  enum :alarm_type, { intrusion: 0, fire: 1, panic: 2, tamper: 3, power_failure: 4 }, validate: true

  validates :sensor_zone, numericality: { only_integer: true, in: 1..99, message: :out_of_range }

  before_validation { self.priority = PRIORITIES[alarm_type] if priority.blank? }

  # The type stands inside the sentence, so its name begins with a small letter.
  def summary
    type = I18n.t("enums.alarm_call.alarm_type.#{alarm_type}").downcase_first if alarm_type
    I18n.t("models.alarm_call.summary", type:)
  end

  def detail = I18n.t("models.alarm_call.detail", zone: sensor_zone)
end
