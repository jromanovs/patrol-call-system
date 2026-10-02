json.count @sites.length
json.sites @sites, partial: "api/v1/sites/site", as: :site
