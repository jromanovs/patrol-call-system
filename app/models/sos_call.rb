# A call raised by a crew that asks for help (2.6, BR-21): it has no site,
# only the car that raised it and the place its last signal came from.
class SosCall < Call
  # UPD-09: what the crew sent to help may find.
  OUTCOMES = %w[ help_given false_alarm other ].freeze
  # DYN-19: what a strip shows or depends on.
  STRIP = %w[ status acknowledged_at signals ].freeze

  validates :raised_by, presence: { message: :required }
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validate :place_whole
  validates :accuracy, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :signals, numericality: { greater_than: 0, only_integer: true }
  validates :signalled_at, presence: true
  validate :another_car_sent

  before_validation { self.priority = "critical" if priority.blank? }
  # UPD-13: sending a car says that the signal is seen.
  before_save :acknowledge_by_dispatch, if: -> { will_save_change_to_status?(to: "dispatched") }
  # DYN-19: the strips of every open page of the staff follow the call, and
  # are not read out or sounded again for a change they do not show.
  after_commit :show_strips, if: :strip_changed?

  # DSP-06: the active calls nobody has acknowledged, the oldest first.
  scope :unacknowledged, lambda {
    where(status: ACTIVE, acknowledged_at: nil).includes(:raised_by).order(:received_at, :id)
  }

  # ADD-11, ADD-12: a signal of the car. Its active call takes the new place
  # and counts the signal, and is to be acknowledged again; without an active
  # call one is registered, by the user who asked, if a user did. A signal
  # without a place, or with a place older than the one the call has, leaves
  # the place as it is; a place off the earth, or half a place, is refused.
  def self.signal(car, place, by: nil)
    attempts ||= 0
    transaction(requires_new: true) do
      call = active_of(car)
      call.registered_by = by if call.new_record?
      call if call.update(**call.newer(located(place)), signals: call.signals.to_i + 1, signalled_at: Time.current,
                          acknowledged_at: nil, acknowledged_by: nil)
    end
  rescue ActiveRecord::RecordNotUnique
    # Two first signals at one moment: the second counts in the call of the first.
    (attempts += 1) < 2 ? retry : raise
  end

  # The active call the car raised, held until the signal is counted, or a
  # new one for it. A signal so waits for another signal, or for a step of
  # the call, to end, and then sees the call as that left it (STO-03).
  def self.active_of(car) = where(raised_by: car, status: ACTIVE).lock.first_or_initialize

  # The place a signal brings, taken now unless it says when.
  def self.located(place)
    return {} if place.slice(:latitude, :longitude).compact.empty?

    { **%i[ latitude longitude accuracy ].index_with { |part| place[part] }, placed_at: place[:placed_at] || Time.current }
  end

  def self.on_earth?(place)
    latitude, longitude = place.values_at(:latitude, :longitude)
    latitude.present? && longitude.present? && latitude.between?(-90, 90) && longitude.between?(-180, 180)
  end

  # DSP-06: the strips as every page of the staff shows them, sent to the
  # pages of each language in that language (USR-10), and in English whether
  # or not it is offered, as a page falls back to it. They are sent at once:
  # a broadcast job of Turbo would word them in the language of the request.
  def self.show_strips
    calls = unacknowledged.to_a
    english = I18n.default_locale.to_s
    (Language.offered | [ english ]).each { |language| send_strips(calls, language, :sos, language) }
    # A page opened before the strips had languages listens for the stream
    # without one until it is loaded again; it was drawn in English.
    send_strips(calls, english, :sos)
  end

  def self.send_strips(calls, language, *stream)
    I18n.with_locale(language) do
      Turbo::StreamsChannel.broadcast_replace_to(*stream, target: "sos-strips", partial: "sos_calls/strips", locals: { calls: })
    end
  end

  # The place a signal brought, unless the call has a newer one: the car
  # sent to help is never led back to where the crew was before.
  def newer(place) = placed_at && place[:placed_at] && place[:placed_at] < placed_at ? {} : place

  # UPD-13: who saw the signal first stays; a second Acknowledge changes nothing.
  def acknowledge(user)
    acknowledged_at ? true : update(acknowledged_at: Time.current, acknowledged_by: user)
  end

  def summary = I18n.t("models.sos_call.summary")

  def detail = I18n.t("models.sos_call.detail", car: raised_by.call_sign)

  def place = I18n.t("models.sos_call.place", car: raised_by.call_sign)

  def placed? = latitude.present?

  # When the place was taken, in words, if that was more than a minute
  # before the signal: the car's last kept position, or a message that came
  # late. A position of another day is told with its day.
  def place_time
    return unless placed? && placed_at.present? && placed_at < signalled_at - 1.minute

    I18n.l(placed_at, format: placed_at.to_date == signalled_at.to_date ? "%H:%M" : :default)
  end

  # How well the place is known: not at all, as an earlier position with its
  # time, or by the accuracy the phone gave.
  def place_detail
    return I18n.t("models.sos_call.place_unknown") unless placed?
    return I18n.t("models.sos_call.#{accuracy ? 'accuracy' : 'accuracy_unknown'}", metres: accuracy) unless place_time

    I18n.t("models.sos_call.#{accuracy ? 'last_position_accuracy' : 'last_position'}", time: place_time, metres: accuracy)
  end

  def title = I18n.t("models.sos_call.title", summary:, car: raised_by.call_sign)

  def district = raised_by.district

  # The car sent to help goes to the place of the signal, when there is one.
  def destination = (self if placed?)

  def outcome_choices = OUTCOMES

  private

  def at_site? = false

  def outcome_refusal = :not_for_sos

  def strip_changed? = destroyed? || previously_new_record? || saved_changes.keys.intersect?(STRIP)

  def place_whole
    errors.add(:base, :half_place) if latitude.nil? != longitude.nil?
  end

  def another_car_sent
    return unless patrol_car_id && patrol_car_id == raised_by_id

    errors.add(:base, :own_car, car: raised_by.call_sign)
  end

  def acknowledge_by_dispatch
    self.acknowledged_at ||= dispatched_at
    self.acknowledged_by ||= dispatched_by
  end

  def show_strips = self.class.show_strips
end
