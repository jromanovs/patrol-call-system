module MapsHelper
  # TRK-03: how long ago a car's position came.
  def position_age(time, now = Time.current)
    minutes = ((now - time) / 60).floor
    if minutes < 1 then "just now"
    elsif minutes < 60 then "#{minutes} min ago"
    elsif minutes < 24 * 60 then "#{minutes / 60} h ago"
    else l(time)
    end
  end

  # TRK-03: a car's mark on the map is named by what it shows.
  def car_label(car, position) = "#{car.call_sign}, #{car.status.humanize.downcase}, position #{position_age(position.recorded_at)}"

  # Longitude and latitude of the centre of Riga, where the map opens.
  RIGA = [ 24.1052, 56.9496 ].freeze
  LEGEND = { "critical" => "Critical call", "high" => "High", "normal" => "Normal", "low" => "Low",
             "none" => "No active call" }.freeze
  ARRIVALS = { "waiting" => "Waiting for a car", "sent" => "Car sent, not accepted",
               "unanswered" => "Not accepted for #{Call::REMINDERS} min", "on-the-way" => "Car on the way",
               "on-site" => "Car on site", "far" => "Arrived farther than #{StepPosition::FAR} m from the site",
               "no-position" => "Car on site, the phone gave no position" }.freeze

  # 1.6: the credit the licences of OpenMapTiles and OpenStreetMap ask for.
  def map_credit
    safe_join([ link_to("© OpenMapTiles", "https://openmaptiles.org/"),
                link_to("© OpenStreetMap contributors", "https://www.openstreetmap.org/copyright") ], " ")
  end
end
