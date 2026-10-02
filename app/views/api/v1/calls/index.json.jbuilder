json.count @calls.length
json.calls @calls, partial: "api/v1/calls/call", as: :call
