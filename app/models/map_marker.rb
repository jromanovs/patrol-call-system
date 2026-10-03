# DSP-05: a site on the map, marked by its most urgent active call.
MapMarker = Data.define(:site, :call) do
  # The sites given, each with the active call that comes first on the board.
  def self.for(sites)
    calls = Call.on_board.includes(:patrol_car, :step_positions).where(guarded_site: sites).group_by(&:guarded_site_id)
    sites.map { |site| new(site:, call: calls[site.id]&.first) }
  end

  def priority = call&.priority || "none"

  def letter = call&.priority&.first&.upcase

  def arrival = call&.arrival

  # The marker's name says what its colour and signs show.
  def label = call ? "#{site.name}, #{call.priority} call, #{MapsHelper::ARRIVALS.fetch(arrival).downcase}" : site.name

  # Longitude first, as the map takes it.
  def position = [ site.address.longitude.to_f, site.address.latitude.to_f ]
end
