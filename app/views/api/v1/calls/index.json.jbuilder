json.count @calls.size
json.calls @calls, partial: "api/v1/calls/call", as: :call
