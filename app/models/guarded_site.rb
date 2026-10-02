# Premises guarded under a monitoring contract (2.2).
class GuardedSite < ApplicationRecord
  belongs_to :address
  has_many :calls, dependent: :restrict_with_error

  enum :site_type, { apartment: 0, house: 1, office: 2, shop: 3, warehouse: 4 }, validate: true
  enum :district, { centre: 0, north: 1, south: 2, east: 3, west: 4 }, validate: true
  enum :contract_status, { active: 0, suspended: 1 }, validate: true

  validates :contract_number, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\AC-\d{5}\z/ }
  validates :name, :client_name, presence: true, length: { in: 2..100 }
  validates :keyholder_phone, format: { with: /\A\+\d{8,15}\z/ }
  validates :contract_start_date, presence: true
  validates :access_notes, length: { maximum: 500 }
  # BR-11 when the address is chosen; BR-12: a site keeps an address that the
  # register marks deleted or erroneous later.
  validate :address_existing, if: -> { new_record? || will_save_change_to_address_id? }

  NAMED = %w[ site_type district contract_status ].freeze
  SORTS = %w[ contract_number name client_name address contract_start_date ] + NAMED

  # FLT-04, FLT-05, SRT-02: the site list for a text, filters and an order.
  def self.list(text: nil, filters: {}, sort: nil, direction: nil)
    sites = includes(:address).where(filters.to_h.compact_blank.slice(*NAMED))
    sites = sites.matching(text) if text.to_s.strip.length >= 2
    sites.sorted(SORTS.include?(sort) ? sort : "name", direction == "desc" ? :desc : :asc).order(id: :asc)
  end

  # SRT-02: type, district and contract status follow the alphabet of their
  # names, not the order of the enumeration.
  def self.sorted(column, direction)
    case column
    when "address" then joins(:address).order(Address.arel_table[:full_address].public_send(direction))
    when *NAMED
      names = public_send(column.pluralize).keys.sort
      in_order_of(column.to_sym, direction == :desc ? names.reverse : names)
    else order(column => direction)
    end
  end

  # FLT-04: contract number, name, client or address contain the text,
  # regardless of letter case and Latvian diacritics.
  def self.matching(text)
    pattern = "%#{sanitize_sql_like(text.strip)}%"
    joins(:address).where(<<~SQL.squish, pattern:)
      lower(unaccent(guarded_sites.contract_number || ' ' || guarded_sites.name || ' ' ||
        guarded_sites.client_name || ' ' || addresses.full_address)) LIKE lower(unaccent(:pattern))
    SQL
  end

  def label = "#{name} · #{contract_number}"

  # DEL-02: why a site with calls stays (BR-9).
  def kept_reason
    "Site has #{calls.count} #{'call'.pluralize(calls.count)} and cannot be deleted; suspend the contract instead"
  end

  private

  def address_existing
    errors.add(:address, "is not an existing address in the register") if address && !address.existing?
  end
end
