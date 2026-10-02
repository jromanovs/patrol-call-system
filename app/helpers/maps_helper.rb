module MapsHelper
  # Longitude and latitude of the centre of Riga, where the map opens.
  RIGA = [ 24.1052, 56.9496 ].freeze
  LEGEND = { "critical" => "Critical call", "high" => "High", "normal" => "Normal", "low" => "Low",
             "none" => "No active call" }.freeze
  ARRIVALS = { "waiting" => "Waiting for a car", "on-the-way" => "Car on the way", "on-site" => "Car on site" }.freeze

  # 1.6: the credit the licences of OpenMapTiles and OpenStreetMap ask for.
  def map_credit
    safe_join([ link_to("© OpenMapTiles", "https://openmaptiles.org/"),
                link_to("© OpenStreetMap contributors", "https://www.openstreetmap.org/copyright") ], " ")
  end
end
