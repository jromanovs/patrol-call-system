# DSP-05: a mark on the map — a site with its most urgent active call, or the
# place of a crew's SOS, which has no site (BR-21).
MapMarker = Data.define(:site, :call) do
  # The sites given, each with the active call that comes first on the board.
  def self.for(sites)
    calls = Call.on_board.includes(:patrol_car, :step_positions).where(guarded_site: sites).group_by(&:guarded_site_id)
    sites.map { |site| new(site:, call: calls[site.id]&.first) }
  end

  # The places of the crews that ask for help among the calls given.
  def self.sos(calls) = calls.grep(SosCall).map { |call| new(site: nil, call:) }

  # What the mark stands for and is named after in the page.
  def subject = site || call

  def kind = ("sos" unless site)

  def priority = call&.priority || "none"

  def letter = site ? call&.priority&.first&.upcase : "SOS · #{call.raised_by.call_sign}"

  def arrival = call&.arrival

  # The marker's name says what its colour and signs show.
  def label
    return site.name unless call

    state = MapsHelper::ARRIVALS.fetch(arrival).downcase
    site ? "#{site.name}, #{call.priority} call, #{state}" : "SOS of #{call.raised_by.call_sign}, #{state}"
  end

  # Longitude first, as the map takes it.
  def position
    place = site ? site.address : call
    [ place.longitude.to_f, place.latitude.to_f ]
  end
end
