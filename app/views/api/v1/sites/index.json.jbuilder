json.count @sites.size
json.sites @sites, partial: "api/v1/sites/site", as: :site
