# A patrol car (2.3).
class PatrolCar < ApplicationRecord
  NAMED = %w[ district status ].freeze
  SORTS = %w[ call_sign plate_number model crew_size ] + NAMED
  # BR-5: only call operations set dispatched and on_scene.
  SET_BY_HAND = %w[ available out_of_service ].freeze

  has_many :calls, dependent: :restrict_with_error

  enum :district, { centre: 0, north: 1, south: 2, east: 3, west: 4 }, validate: true
  enum :status, { available: 0, dispatched: 1, on_scene: 2, out_of_service: 3 }, validate: true

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

  def active_call = calls.where(status: Call::ACTIVE).order(:received_at).first

  private

  # BR-6
  def without_active_call
    call = active_call or return
    errors.add(:status, "cannot be out of service: active call at #{call.guarded_site.name}, " \
                        "received #{I18n.l(call.received_at)}")
  end
end
