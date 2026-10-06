module MapsHelper
  # TRK-03: how long ago a car's position came.
  def position_age(time, now = Time.current)
    minutes = ((now - time) / 60).floor
    if minutes < 1 then t("maps.position_age.just_now")
    elsif minutes < 60 then t("maps.position_age.minutes", count: minutes)
    elsif minutes < 24 * 60 then t("maps.position_age.hours", count: minutes / 60)
    else l(time)
    end
  end

  # TRK-03: a car's mark on the map is named by what it shows; the status
  # stands inside the sentence, so its name begins with a small letter.
  def car_label(car, position)
    t("maps.car_label", car: car.call_sign, status: enum_name(PatrolCar, :status, car.status).downcase_first,
                        age: position_age(position.recorded_at))
  end

  # Longitude and latitude of the centre of Riga, where the map opens.
  RIGA = [ 24.1052, 56.9496 ].freeze
  # DSP-05: what the legend explains, in its order: the priorities of a call,
  # and where the car of a call is.
  LEGEND = %w[ critical high normal low none ].freeze
  ARRIVALS = %w[ waiting sent unanswered on-the-way on-site far no-position ].freeze

  # Where the car of a call is, in the words of the legend.
  def arrival_words(arrival) = t("maps.arrivals.#{arrival}", minutes: Call::REMINDERS, metres: StepPosition::FAR)

  # 1.6: the credit the licences of OpenMapTiles and OpenStreetMap ask for.
  def map_credit
    safe_join([ link_to(t("maps.credit.tiles"), "https://openmaptiles.org/"),
                link_to(t("maps.credit.data"), "https://www.openstreetmap.org/copyright") ], " ")
  end
end
