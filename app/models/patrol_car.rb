# A patrol car (2.3).
class PatrolCar < ApplicationRecord
  NAMED = %w[ district status ].freeze
  SORTS = %w[ call_sign plate_number model crew_size ] + NAMED
  # BR-5: only call operations set dispatched and on_scene.
  SET_BY_HAND = %w[ available out_of_service ].freeze
  # TRK-01: each source in the words of the tracking page and of its message.
  SOURCES = { "not_tracked" => "Not tracked", "traccar" => "Traccar Client", "crew_phone" => "Crew's phone" }.freeze
  TRACKED = { "not_tracked" => "is not tracked", "traccar" => "is tracked by Traccar Client",
              "crew_phone" => "is tracked by the crew's phone" }.freeze

  has_many :calls, dependent: :restrict_with_error
  # BR-21: the calls its crew raised by an SOS; they keep the car as well.
  has_many :raised_calls, class_name: "SosCall", foreign_key: :raised_by_id, inverse_of: :raised_by,
                          dependent: :restrict_with_error
  # BR-22: the calls it was sent to as a further car; they keep the car too.
  has_many :backups, dependent: :restrict_with_error
  has_many :crew, class_name: "User", dependent: :restrict_with_error
  # TRK-03, BR-20: where the car's phone said it was, for the period the
  # administrator set; while any is kept, the car is too.
  has_many :car_positions, dependent: :restrict_with_error

  include StatusTransitions

  enum :district, { centre: 0, north: 1, south: 2, east: 3, west: 4 }, validate: true
  enum :status, { available: 0, dispatched: 1, on_scene: 2, out_of_service: 3 }, validate: true
  # BR-20: where the car's position comes from.
  enum :position_source, { not_tracked: 0, traccar: 1, crew_phone: 2 }, validate: true

  transitions available: %i[ dispatched out_of_service ], dispatched: %i[ on_scene available ],
              on_scene: :available, out_of_service: :available

  normalizes :plate_number, with: ->(plate) { plate.strip.upcase }

  # DYN-02: every open board reloads after any change of a car.
  broadcasts_refreshes_to ->(_car) { :board }

  validates :call_sign, uniqueness: true, format: { with: /\A[A-Z]{1,3}-\d{1,3}\z/ }
  validates :plate_number, uniqueness: true, format: { with: /\A[A-Z0-9-]{2,10}\z/ }
  validates :model, presence: true, length: { in: 2..50 }
  validates :crew_size, numericality: { only_integer: true, in: 1..4, message: "must be between 1 and 4" }
  validate :without_active_call, if: -> { will_save_change_to_status?(to: "out_of_service") }

  # FLT-06, SRT-03: the car list for a text, filters and an order.
  def self.list(text: nil, filters: {}, sort: nil, direction: nil)
    cars = where(filters.to_h.compact_blank.slice(*NAMED))
    cars = cars.matching(text) if text.to_s.strip.length >= 2
    cars.sorted(SORTS.include?(sort) ? sort : "call_sign", direction == "desc" ? :desc : :asc).order(id: :asc)
  end

  def self.matching(text)
    where("lower(call_sign || ' ' || plate_number || ' ' || model) LIKE lower(?)", "%#{sanitize_sql_like(text.strip)}%")
  end

  # District and status follow the alphabet of their names.
  def self.sorted(column, direction)
    return order(column => direction) unless NAMED.include?(column)

    names = public_send(column.pluralize).keys.sort
    in_order_of(column.to_sym, direction == :desc ? names.reverse : names)
  end

  # DSP-03: free cars first, then by call sign.
  def self.on_panel = in_order_of(:status, statuses.keys).order(:call_sign)

  # The call it serves now, as the call's own car or as a further car.
  def active_call = calls.where(status: Call::ACTIVE).order(:received_at).first || backups.active.first&.call

  def tracked? = !not_tracked?

  def tracked_words = "#{call_sign} #{TRACKED.fetch(position_source)}"

  # TRK-02, BR-20: the car whose Traccar Client sends this identifier. The
  # identifier is random and long, so a plain digest is enough to find it and
  # nothing to recover it from.
  def self.find_by_tracking_key(key)
    find_by(tracking_key_digest: Digest::SHA256.hexdigest(key)) if key.present?
  end

  # A new identifier replaces the old one; only its digest and a hint are kept.
  def issue_tracking_key
    SecureRandom.base58(32).tap do |key|
      update!(tracking_key_digest: Digest::SHA256.hexdigest(key), tracking_key_hint: "#{key.first(4)}…#{key.last(4)}",
              tracking_key_issued_at: Time.current)
    end
  end

  # BR-5: by hand the status changes only between available and out of
  # service, and not while a call holds the car; any other status is left out.
  def self.by_hand(fields, car = nil)
    allowed = SET_BY_HAND.include?(fields[:status]) && (car.nil? || car.status.in?(SET_BY_HAND))
    allowed ? fields : fields.except(:status)
  end

  # DEL-04: why a car with crew users, calls or kept positions stays (BR-9,
  # BR-20).
  def kept_reason
    if crew.exists?
      return "Car has #{crew.count} crew #{'user'.pluralize(crew.count)} and cannot be deleted; " \
             "move them to another car first"
    end

    kept = calls.count + raised_calls.count + backups.count
    held = kept.zero? ? "positions kept since #{I18n.l(car_positions.kept_since)}" : "#{kept} #{'call'.pluralize(kept)}"
    "Car has #{held} and cannot be deleted; put it out of service instead"
  end

  private

  # BR-6
  def without_active_call
    call = active_call or return
    errors.add(:status, "cannot be out of service: active call at #{call.place}, " \
                        "received #{I18n.l(call.received_at)}")
  end
end
