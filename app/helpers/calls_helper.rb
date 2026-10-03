module CallsHelper
  # FLT-01, DEL-07: the kinds of calls by their names.
  KINDS = [ %w[ Alarm alarm ], [ "Client call", "client" ], [ "Crew's SOS", "sos" ] ].freeze

  # FLT-01: the choices of each select filter of the call list, in their order.
  def call_filter_options
    {
      status: enum_options(Call, :status),
      priority: enum_options(Call, :priority).reverse,
      kind: KINDS,
      district: enum_options(GuardedSite, :district),
      site_id: GuardedSite.order(:name).pluck(:name, :id),
      car_id: PatrolCar.order(:call_sign).pluck(:call_sign, :id)
    }
  end

  # DSP-02: whole minutes between two steps of the timeline, seconds dropped as
  # in the handling time, so a call cancelled before dispatch shows the same
  # minutes in the step and in the total.
  def minutes_between(later, earlier) = ((later - earlier) / 60).floor

  # CRW-08: directions by car to the site in Google Maps, in its app when the
  # phone has it (Maps URLs need no key).
  def route_url(address)
    "https://www.google.com/maps/dir/?api=1&destination=#{address.latitude},#{address.longitude}&travelmode=driving"
  end

  # DSP-02: where a call of the car page leads: to its site, or, for a crew's
  # SOS, which has none, to the call itself (BR-21).
  def call_place_path(call) = call.guarded_site_id ? guarded_site_path(call.guarded_site_id) : call_path(call)

  # CRW-07: the crew's step forms take where the phone is; the staff's none.
  def crew_position_data = Current.user&.crew? ? { controller: "position", action: "submit->position#locate turbo:submit-end->position#reset" } : {}

  # DSP-02, CRW-07: where the crew's phone was at a step, or that it is
  # unknown; farther than 200 m, a warning (CRW-09).
  def step_position_text(position)
    return "Position unknown · #{position.user.name}" unless position.known?
    return "The place of the signal is unknown (#{coordinates(position)}) · #{position.user.name}" unless position.distance

    far = " — farther than #{StepPosition::FAR} m" if position.far?
    accuracy = " · accuracy #{position.accuracy} m" if position.accuracy
    format("%<distance>s m from #{goal(position)}%<far>s%<accuracy>s (%<latitude>.6f, %<longitude>.6f) · %<name>s",
           distance: number_with_delimiter(position.distance, delimiter: "\u00a0"), far:, accuracy:,
           latitude: position.latitude, longitude: position.longitude, name: position.user.name)
  end

  # CRW-09: a distance from the site in metres, from a kilometre on in
  # kilometres with one decimal.
  def distance_words(metres) = metres < 1000 ? "#{metres} m" : "#{(metres / 1000.0).round(1)} km"

  # CRW-09: where the crew marked Arrived, said after the time of arrival.
  def arrival_place(position)
    if position.nil? then "by radio, no position"
    elsif position.known? && position.distance.nil? then "the place of the signal is unknown"
    elsif position.known? then "#{distance_words(position.distance)} from #{goal(position)}"
    else "the phone gave no position"
    end
  end

  # CRW-09: the warning of an arrival marked far from the site.
  def far_arrival_text(car, position)
    accuracy = " · accuracy #{position.accuracy} m" if position.accuracy
    "#{car} marked Arrived #{distance_words(position.distance)} from #{goal(position)}#{accuracy}"
  end

  def coordinates(place) = format("%<latitude>.6f, %<longitude>.6f", latitude: place.latitude, longitude: place.longitude)

  # BR-21: a crew's SOS has no site; its distances are from the place of its signal.
  def goal(position) = position.call.guarded_site_id ? "the site" : "the place of the signal"

  # CRW-11: the times of a car's steps towards the crew that asked for help.
  def steps_words(sent_at, accepted_at, arrived_at)
    time = ->(at) { l(at, format: "%H:%M") }
    [ time.call(sent_at), ("accepted at #{time.call(accepted_at)}" if accepted_at),
      ("arrived at #{time.call(arrived_at)}" if arrived_at) ].compact.join(" · ")
  end

  # CRW-10: the photo controller hears the server's answer, holds a refresh
  # of the page while photos are on their way, gets ready for the next
  # choice, and after a refresh in place still offers photos not sent.
  def photo_wiring = "turbo:before-fetch-response@document->photo#answer turbo:before-visit@document->photo#hold " \
                     "turbo:submit-end@document->photo#reset turbo:morph@document->photo#restore"
end
