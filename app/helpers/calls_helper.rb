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

  # DSP-02, CRW-07: where the crew's phone was at a step, or that it is unknown.
  def step_position_text(position)
    place = if position.known?
              accuracy = ", accuracy #{position.accuracy} m" if position.accuracy
              format("%<distance>d m from the site%<accuracy>s (%<latitude>.6f, %<longitude>.6f)",
                     distance: position.distance, accuracy:, latitude: position.latitude, longitude: position.longitude)
    else
              "Position unknown"
    end
    "#{place} · #{position.user.name}"
  end
end
