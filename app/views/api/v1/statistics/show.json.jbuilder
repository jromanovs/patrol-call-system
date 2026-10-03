json.period do
  json.from @filter.from&.iso8601
  json.to @filter.to&.iso8601
end
json.total @statistics.total
json.by_status @statistics.by_status.to_h
json.by_outcome @statistics.by_outcome.to_h
json.response do
  json.arrivals @statistics.arrivals
  json.average @statistics.response
  json.by_priority(@statistics.response_by_priority.to_h do |priority, count, average|
    [ priority, { arrivals: count, average: } ]
  end)
  json.by_car @statistics.response_by_car do |car, count, average|
    json.id car.id
    json.call_sign car.call_sign
    json.arrivals count
    json.average average
  end
end
json.acceptance do
  json.accepted @statistics.acceptances
  json.average @statistics.acceptance
end
json.false_alarms do
  alarms = @statistics.false_alarms
  json.count alarms.count
  json.closed alarms.closed
  json.share alarms.share
end
json.false_alarm_sites @statistics.false_alarm_sites do |site, count|
  json.id site.id
  json.name site.name
  json.contract_number site.contract_number
  json.count count
end
