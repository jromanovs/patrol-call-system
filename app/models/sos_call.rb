# A call raised by a crew that asks for help (2.6, BR-21): it has no site,
# only the car that raised it and the place its last signal came from.
class SosCall < Call
  # UPD-09: what the crew sent to help may find.
  OUTCOMES = %w[ help_given false_alarm other ].freeze

  validates :raised_by, presence: { message: "must exist" }
  validates :latitude, numericality: { in: -90..90 }
  validates :longitude, numericality: { in: -180..180 }
  validates :accuracy, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :signals, numericality: { greater_than: 0, only_integer: true }
  validate :another_car_sent

  before_validation { self.priority = "critical" if priority.blank? }
  # UPD-13: sending a car says that the signal is seen.
  before_save :acknowledge_by_dispatch, if: -> { will_save_change_to_status?(to: "dispatched") }
  # DYN-19: the strip of every open page of the staff follows the call.
  after_commit :show_strips

  # DSP-06: the active calls nobody has acknowledged, the oldest first.
  scope :unacknowledged, lambda {
    where(status: ACTIVE, acknowledged_at: nil).includes(:raised_by).order(:received_at, :id)
  }

  # ADD-11: a signal of the car. Its active call takes the new place and
  # counts the signal, and is to be acknowledged again; without an active
  # call one is registered. Nothing is kept without a place on the earth.
  def self.signal(car, place)
    attempts ||= 0
    call = active_of(car)
    counted = transaction(requires_new: true) do
      call.update(**place.slice(:latitude, :longitude, :accuracy), signals: call.signals.to_i + 1,
                  signalled_at: Time.current, acknowledged_at: nil, acknowledged_by: nil)
    end
    call if counted
  rescue ActiveRecord::RecordNotUnique
    # Two signals at one moment: the second counts in the call of the first.
    (attempts += 1) < 2 ? retry : raise
  end

  # The active call the car raised, or a new one for it.
  def self.active_of(car) = where(raised_by: car, status: ACTIVE).first_or_initialize

  # DSP-06: the strips as every page of the staff shows them.
  def self.show_strips
    Turbo::StreamsChannel.broadcast_replace_to(:sos, target: "sos-strips", partial: "sos_calls/strips",
                                                     locals: { calls: unacknowledged.to_a })
  end

  # UPD-13: who saw the signal first stays; a second Acknowledge changes nothing.
  def acknowledge(user)
    acknowledged_at ? true : update(acknowledged_at: Time.current, acknowledged_by: user)
  end

  def summary = "Crew's SOS"

  def detail = "From #{raised_by.call_sign}"

  def place = "Crew of #{raised_by.call_sign}"

  def place_detail = accuracy ? "Position accuracy #{accuracy} m" : "Position accuracy unknown"

  def title = "#{summary} from #{raised_by.call_sign}"

  def district = raised_by.district

  # The car sent to help goes to the place of the signal.
  def destination = self

  def outcome_choices = OUTCOMES

  private

  def at_site? = false

  def another_car_sent
    return unless patrol_car_id && patrol_car_id == raised_by_id

    errors.add(:base, "#{raised_by.call_sign} raised this call and cannot be sent to it")
  end

  def acknowledge_by_dispatch
    self.acknowledged_at ||= dispatched_at
    self.acknowledged_by ||= dispatched_by
  end

  def show_strips = self.class.show_strips
end
