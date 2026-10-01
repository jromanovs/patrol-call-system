# Demo data (SPECIFICATION.md 1.5): addresses of public buildings from the
# State Address Register (data.gov.lv, dataset varis-atvertie-dati, file
# aw_eka.csv, licence CC BY 4.0, read on 2026-10-01) with fictitious clients
# and phone numbers. Running it again changes nothing.

addresses = [
  { code: 101_838_146, full_address: "Jēkaba iela 11, Rīga, LV-1050", postal_code: "LV-1050",
    latitude: 56.9512, longitude: 24.104642, register_updated_on: "2003-01-10" },
  { code: 102_697_576, full_address: "Raiņa bulvāris 19, Rīga, LV-1050", postal_code: "LV-1050",
    latitude: 56.950806, longitude: 24.116314, register_updated_on: "2003-01-10" },
  { code: 106_306_366, full_address: "Pils laukums 3, Rīga, LV-1050", postal_code: "LV-1050",
    latitude: 56.951055, longitude: 24.100933, register_updated_on: "2012-04-04" },
  { code: 105_640_222, full_address: "Mūkusalas iela 3, Rīga, LV-1048", postal_code: "LV-1048",
    latitude: 56.941344, longitude: 24.096641, register_updated_on: "2013-10-01" },
  { code: 101_816_555, full_address: "Aspazijas bulvāris 3, Rīga, LV-1050", postal_code: "LV-1050",
    latitude: 56.94924, longitude: 24.11418, register_updated_on: "2025-05-07" },
  { code: 101_818_438, full_address: "Ķīpsalas iela 6, Rīga, LV-1048", postal_code: "LV-1048",
    latitude: 56.953338, longitude: 24.082275, register_updated_on: "2017-08-09" }
].to_h do |attributes|
  [ attributes[:code], Address.find_or_create_by!(code: attributes[:code]) { |address| address.assign_attributes(attributes) } ]
end

[
  { contract_number: "C-00011", name: "Demo Office 1", client_name: "Example Holding Ltd", address: 101_838_146,
    site_type: :office, district: :centre, keyholder_phone: "+37100000011", contract_start_date: "2026-03-01" },
  { contract_number: "C-00012", name: "Demo Shop 2", client_name: "Sample Retail Ltd", address: 101_816_555,
    site_type: :shop, district: :centre, keyholder_phone: "+37100000012", contract_start_date: "2026-04-15" },
  { contract_number: "C-00013", name: "Demo Warehouse 3", client_name: "Example Trade Ltd", address: 105_640_222,
    site_type: :warehouse, district: :south, keyholder_phone: "+37100000013", contract_start_date: "2026-05-20" },
  { contract_number: "C-00014", name: "Demo Office 4", client_name: "Test Services Ltd", address: 101_818_438,
    site_type: :office, district: :west, keyholder_phone: "+37100000014", contract_start_date: "2026-02-01",
    contract_status: :suspended }
].each do |attributes|
  GuardedSite.find_or_create_by!(contract_number: attributes[:contract_number]) do |site|
    site.assign_attributes(attributes.merge(address: addresses.fetch(attributes[:address])))
  end
end

# Cars with fictitious plates; P-21 is out of service.
[
  { call_sign: "P-12", plate_number: "ZZ-0012", model: "Skoda Octavia", crew_size: 2, district: :centre },
  { call_sign: "P-15", plate_number: "ZZ-0015", model: "Toyota Corolla", crew_size: 2, district: :north },
  { call_sign: "P-07", plate_number: "ZZ-0007", model: "Skoda Octavia", crew_size: 2, district: :east },
  { call_sign: "P-03", plate_number: "ZZ-0003", model: "VW Passat", crew_size: 3, district: :south },
  { call_sign: "P-21", plate_number: "ZZ-0021", model: "Skoda Octavia", crew_size: 2, district: :west,
    status: :out_of_service }
].each do |attributes|
  PatrolCar.find_or_create_by!(call_sign: attributes[:call_sign]) { |car| car.assign_attributes(attributes) }
end
