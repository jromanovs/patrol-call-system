json.id call.id
json.kind Api::V1::CallsController::KINDS.fetch(call.class)
json.call(call, :priority, :status, :outcome, :alarm_type, :sensor_zone, :caller_name, :caller_phone, :description)
if call.guarded_site
  json.site { json.call(call.guarded_site, :id, :name, :contract_number) }
else
  json.site nil
end
if call.patrol_car
  json.car { json.call(call.patrol_car, :id, :call_sign) }
else
  json.car nil
end
%i[ received_at dispatched_at accepted_at arrived_at closed_at ].each { |step| json.set! step, call.public_send(step)&.iso8601 }
json.response_minutes call.response_minutes
json.handling_minutes call.handling_minutes
json.registered_by call.registered_by&.name
json.dispatched_by call.dispatched_by&.name
# BR-21: what only a crew's SOS has; null for a call at a site.
if call.raised_by
  json.raised_by { json.call(call.raised_by, :id, :call_sign) }
  json.place { json.merge!(latitude: call.latitude.to_f, longitude: call.longitude.to_f, accuracy: call.accuracy) }
else
  json.raised_by nil
  json.place nil
end
json.signals call.signals
json.signalled_at call.signalled_at&.iso8601
json.acknowledged_at call.acknowledged_at&.iso8601
json.acknowledged_by call.acknowledged_by&.name
