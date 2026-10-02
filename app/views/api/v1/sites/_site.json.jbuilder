json.call(site, :id, :contract_number, :name, :client_name, :site_type, :district, :contract_status, :keyholder_phone,
          :contract_start_date)
json.address do
  json.call(site.address, :code, :full_address, :postal_code, :status)
  json.latitude site.address.latitude.to_f
  json.longitude site.address.longitude.to_f
end
