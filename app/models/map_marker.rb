# DSP-05: a mark on the map — a site with its most urgent active call, or the
# place of a crew's SOS, which has no site (BR-21).
MapMarker = Data.define(:site, :call) do
  # The sites given, each with the active call that comes first on the board.
  def self.for(sites)
    calls = Call.on_board.includes(:patrol_car, :step_positions).where(guarded_site: sites).group_by(&:guarded_site_id)
    sites.map { |site| new(site:, call: calls[site.id]&.first) }
  end

  # The places of the crews that ask for help among the calls given; a
  # signal without a place has no mark.
  def self.sos(calls) = calls.grep(SosCall).select(&:placed?).map { |call| new(site: nil, call:) }

  # The letter a mark shows for a priority: the first of its name.
  def self.letter_of(priority) = I18n.t("enums.call.priority.#{priority}").first.upcase

  # What the mark stands for and is named after in the page.
  def subject = site || call

  def kind = ("sos" unless site)

  def priority = call&.priority || "none"

  def letter
    return "#{I18n.t('common.sos')} · #{call.raised_by.call_sign}" unless site

    self.class.letter_of(call.priority) if call
  end

  def arrival = call&.arrival

  # The marker's name says what its colour and signs show; the priority
  # stands inside the sentence, so its name begins with a small letter.
  def label
    return site.name unless call
    return I18n.t("models.map_marker.sos", car: call.raised_by.call_sign, state:) unless site

    I18n.t("models.map_marker.site", site: site.name, state:,
                                     priority: I18n.t("enums.call.priority.#{call.priority}").downcase_first)
  end

  # Where the car of the call is, in the words of the legend, inside a
  # sentence. A crew's SOS has no site to be far from (BR-21).
  def state
    return I18n.t("models.map_marker.far_from_signal", metres: StepPosition::FAR) if arrival == "far" && site.nil?

    I18n.t("maps.arrivals.#{arrival}", minutes: Call::REMINDERS, metres: StepPosition::FAR).downcase_first
  end

  # Longitude first, as the map takes it.
  def position
    place = site ? site.address : call
    [ place.longitude.to_f, place.latitude.to_f ]
  end
end
