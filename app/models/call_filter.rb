# FLT-01 … FLT-03, SRT-01: the calls that match the chosen criteria, in the
# chosen order; equal values follow the received time, newest first.
class CallFilter
  include ActiveModel::Model
  include ActiveModel::Attributes

  KINDS = { "alarm" => "AlarmCall", "client" => "ClientCall", "sos" => "SosCall" }.freeze
  SORTS = %w[ received_at priority site type status car outcome time response ].freeze
  URGENCY = %w[ critical high normal low ].freeze

  attribute :q, :string
  attribute :status, :string
  attribute :priority, :string
  attribute :kind, :string
  attribute :district, :string
  attribute :site_id, :integer
  attribute :car_id, :integer
  attribute :from, :date
  attribute :to, :date
  attribute :sort, :string
  attribute :direction, :string

  validate :period_in_order

  def results = ordered(selected.includes(:patrol_car, :guarded_site, :backups))

  # The matching calls in no order, for counting (CALC-01 … CALC-04).
  def selected
    calls = Call.where(plain_criteria)
    calls = calls.joins(:guarded_site).where(guarded_sites: { district: }) if district.present?
    calls = calls.where(received_at: period) if period
    q.to_s.strip.length >= 2 ? matching(calls) : calls
  end

  def short_text? = q.present? && q.strip.length < 2

  def active? = [ q, status, priority, kind, district, site_id, car_id, from, to ].any?(&:present?)

  private

  def plain_criteria
    { status:, priority:, type: KINDS[kind], guarded_site_id: site_id, patrol_car_id: car_id }.compact_blank
  end

  # FLT-02: whole days in Riga time; no period when its start is after its end.
  def period
    return if (from.nil? && to.nil?) || (from && to && from > to)

    from&.in_time_zone&.beginning_of_day..to&.in_time_zone&.end_of_day
  end

  # A call at a site is found by the site, its contract or the caller; a
  # crew's SOS, which has no site, by the car that raised it (BR-21).
  def matching(calls)
    pattern = "%#{Call.sanitize_sql_like(q.strip)}%"
    calls.left_joins(:guarded_site).joins("LEFT JOIN patrol_cars raisers ON raisers.id = calls.raised_by_id")
         .where(<<~SQL.squish, pattern:)
           lower(unaccent(concat_ws(' ', guarded_sites.name, guarded_sites.contract_number, calls.caller_name,
             raisers.call_sign))) LIKE lower(unaccent(:pattern))
         SQL
  end

  def ordered(calls)
    column = SORTS.include?(sort) ? sort : "received_at"
    sorted(calls, column, way(column)).order(received_at: :desc, id: :desc)
  end

  # The received time starts newest first; every other column A to Z.
  def way(column)
    return direction.to_sym if %w[ asc desc ].include?(direction)

    column == "received_at" ? :desc : :asc
  end

  def sorted(calls, column, way)
    case column
    when "received_at" then calls.order(received_at: way)
    when "priority" then calls.in_order_of(:priority, way == :asc ? URGENCY : URGENCY.reverse)
    when "site" then calls.left_joins(:guarded_site).order(GuardedSite.arel_table[:name].public_send(way).nulls_last)
    when "car" then calls.left_joins(:patrol_car).order(PatrolCar.arel_table[:call_sign].public_send(way).nulls_last)
    when "type" then calls.order(type: way)
    when "time", "response" then calls.order(span(column).public_send(way).nulls_last)
    else by_name(calls, column, way)
    end
  end

  # 2.10: the handling time runs until now for an active call; the response
  # time is empty until the crew arrives.
  def span(column)
    table = Call.arel_table
    finish = if column == "time"
      Arel::Nodes::NamedFunction.new("COALESCE", [ table[:closed_at], Arel::Nodes.build_quoted(Time.current) ])
    else
      Arel.sql(Call::FIRST_ARRIVAL)
    end
    Arel::Nodes::Subtraction.new(finish, table[:received_at])
  end

  # Status and outcome follow the alphabet of their names; a call without an
  # outcome comes last.
  def by_name(calls, column, way)
    names = Call.public_send(column.pluralize).keys.sort
    calls.in_order_of(column.to_sym, way == :asc ? names : names.reverse, filter: false)
  end

  def period_in_order
    errors.add(:base, :period_reversed) if from && to && from > to
  end
end
