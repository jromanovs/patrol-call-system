# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "altcha" # @3.2.4

# DSP-05: the map libraries keep the file names they import each other by, so
# they are served from public/vendor; the map controller loads them, and
# pmtiles, only on pages with a map.
pin "maplibre-gl", to: "/vendor/maplibre-gl-6.11.2/maplibre-gl.mjs", preload: false
pin_all_from "app/javascript/map", under: "map", preload: false
