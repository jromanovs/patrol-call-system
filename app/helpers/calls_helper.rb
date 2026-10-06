module CallsHelper
  # FLT-01, DEL-07: the kinds of calls by their names, as the choices of a select.
  def call_kinds(kinds = CallFilter::KINDS.keys) = kinds.map { |kind| [ t("calls.kinds.#{kind}"), kind ] }

  # FLT-01: the choices of each select filter of the call list, in their order.
  def call_filter_options
    {
      status: enum_options(Call, :status),
      priority: enum_options(Call, :priority).reverse,
      kind: call_kinds,
      district: enum_options(GuardedSite, :district),
      site_id: GuardedSite.order(:name).pluck(:name, :id),
      car_id: PatrolCar.order(:call_sign).pluck(:call_sign, :id)
    }
  end

  # DSP-02: whole minutes between two steps of the timeline, seconds dropped as
  # in the handling time, so a call cancelled before dispatch shows the same
  # minutes in the step and in the total.
  def minutes_between(later, earlier) = ((later - earlier) / 60).floor

  # DSP-02: the description of a call, then the note of its closing or the
  # reason of its cancellation under a name in the language of the reader
  # (USR-10).
  def call_description(call)
    [ call.description.presence,
      (t("calls.show.closing_note", text: call.closing_note) if call.closing_note.present?),
      (t("calls.show.cancellation_reason", text: call.cancellation_reason) if call.cancellation_reason.present?) ].compact.join("\n")
  end

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
  # unknown; farther than 200 m, a warning (CRW-09). The facts stand in a row,
  # each whole in its translation.
  def step_position_text(position)
    name = position.user.name
    return "#{t('calls.position.unknown')} · #{name}" unless position.known?

    place = coordinates(position)
    return "#{t('calls.position.no_signal_place', coordinates: place)} · #{name}" unless position.distance

    metres = t("calls.position.metres", number: number_with_delimiter(position.distance, delimiter: "\u00a0"))
    "#{[ distance_from_goal(position, metres, far: position.far?), accuracy_words(position) ].compact.join(' · ')} " \
      "(#{place}) · #{name}"
  end

  # CRW-09: a distance from the site in metres, from a kilometre on in
  # kilometres with one decimal.
  def distance_words(metres)
    return t("calls.position.metres", number: metres) if metres < 1000

    t("calls.position.kilometres", number: (metres / 1000.0).round(1))
  end

  # CRW-09: where the crew marked Arrived, said after the time of arrival.
  def arrival_place(position)
    if position.nil? then t("calls.position.by_radio")
    elsif position.known? && position.distance.nil? then t("calls.position.signal_place_unknown")
    elsif position.known? then distance_from_goal(position, distance_words(position.distance))
    else t("calls.position.not_given")
    end
  end

  # CRW-09: the warning of an arrival marked far from the site.
  def far_arrival_text(car, position)
    marked = t("calls.position.marked_from_#{goal(position)}", car:, distance: distance_words(position.distance))
    [ marked, accuracy_words(position) ].compact.join(" · ")
  end

  def coordinates(place) = format("%<latitude>.6f, %<longitude>.6f", latitude: place.latitude, longitude: place.longitude)

  # BR-21: a crew's SOS has no site; its distances are from the place of its
  # signal. The name of the goal is a part of the keys of the translations.
  def goal(position) = position.call.guarded_site_id ? "site" : "signal"

  def distance_from_goal(position, distance, far: false)
    t("calls.position.#{'far_' if far}from_#{goal(position)}", distance:, metres: StepPosition::FAR)
  end

  # How exact a place is, where the phone told it.
  def accuracy_words(place) = (t("calls.position.accuracy", metres: place.accuracy) if place.accuracy)

  # CRW-11: the steps of a car towards the crew that asked for help: the
  # first, as the page words it, then the times of the acceptance and of the
  # arrival.
  def steps_words(first, accepted_at, arrived_at)
    time = ->(at) { l(at, format: "%H:%M") }
    [ first, (t("crews.sos_state.accepted_at", time: time.call(accepted_at)) if accepted_at),
      (t("crews.sos_state.arrived_at", time: time.call(arrived_at)) if arrived_at) ].compact.join(" · ")
  end

  # CRW-10: the photo controller hears the server's answer, holds a refresh
  # of the page while photos are on their way, gets ready for the next
  # choice, and after a refresh in place still offers photos not sent.
  def photo_wiring = "turbo:before-fetch-response@document->photo#answer turbo:before-visit@document->photo#hold " \
                     "turbo:submit-end@document->photo#reset turbo:morph@document->photo#restore"

  # CRW-10: what the photo controller says while photos are on their way and
  # when they did not reach the server; it takes its words from the page.
  def photo_words
    { photo_sending_text_value: t("calls.photo_status.sending"), photo_unsent_text_value: t("calls.photo_status.unsent") }
  end
end
