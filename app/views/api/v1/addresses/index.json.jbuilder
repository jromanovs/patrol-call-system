json.count @addresses.length
json.addresses @addresses do |address|
  json.call(address, :code, :full_address, :postal_code)
  json.latitude address.latitude.to_f
  json.longitude address.longitude.to_f
end
