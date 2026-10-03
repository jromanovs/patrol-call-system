json.id call.id
json.kind call.is_a?(AlarmCall) ? "alarm" : "client"
json.call(call, :priority, :status, :outcome, :alarm_type, :sensor_zone, :caller_name, :caller_phone, :description)
json.site do
  json.call(call.guarded_site, :id, :name, :contract_number)
end
if call.patrol_car
  json.car { json.call(call.patrol_car, :id, :call_sign) }
else
  json.car nil
end
%i[ received_at dispatched_at accepted_at arrived_at closed_at ].each { |step| json.set! step, call.public_send(step)&.iso8601 }
json.response_minutes call.response_minutes
json.handling_minutes call.handling_minutes
json.registered_by call.registered_by.name
json.dispatched_by call.dispatched_by&.name
