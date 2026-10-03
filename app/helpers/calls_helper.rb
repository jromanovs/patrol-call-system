module CallsHelper
  # FLT-01: the choices of each select filter of the call list, in their order.
  def call_filter_options
    {
      status: enum_options(Call, :status),
      priority: enum_options(Call, :priority).reverse,
      kind: [ %w[ Alarm alarm ], [ "Client call", "client" ] ],
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

  # CRW-07: the crew's step forms take where the phone is; the staff's none.
  def crew_position_data = Current.user&.crew? ? { controller: "position", action: "submit->position#locate turbo:submit-end->position#reset" } : {}

  # DSP-02, CRW-07: where the crew's phone was at a step, or that it is
  # unknown; farther than 200 m, a warning (CRW-09).
  def step_position_text(position)
    return "Position unknown · #{position.user.name}" unless position.known?

    far = " — farther than #{StepPosition::FAR} m" if position.far?
    accuracy = " · accuracy #{position.accuracy} m" if position.accuracy
    format("%<distance>s m from the site%<far>s%<accuracy>s (%<latitude>.6f, %<longitude>.6f) · %<name>s",
           distance: number_with_delimiter(position.distance, delimiter: "\u00a0"), far:, accuracy:,
           latitude: position.latitude, longitude: position.longitude, name: position.user.name)
  end

  # CRW-09: a distance from the site in metres, from a kilometre on in
  # kilometres with one decimal.
  def distance_words(metres) = metres < 1000 ? "#{metres} m" : "#{(metres / 1000.0).round(1)} km"

  # CRW-09: where the crew marked Arrived, said after the time of arrival.
  def arrival_place(position)
    if position.nil? then "by radio, no position"
    elsif position.known? then "#{distance_words(position.distance)} from the site"
    else "the phone gave no position"
    end
  end

  # CRW-09: the warning of an arrival marked far from the site.
  def far_arrival_text(car, position)
    accuracy = " · accuracy #{position.accuracy} m" if position.accuracy
    "#{car} marked Arrived #{distance_words(position.distance)} from the site#{accuracy}"
  end
end
