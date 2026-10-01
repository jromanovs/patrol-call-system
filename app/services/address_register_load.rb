require "csv"

# ADD-09, ADD-10: loads the addresses of one city from the State Address
# Register file aw_eka.csv. Addresses are created or updated by their code and
# never deleted (BR-12).
class AddressRegisterLoad
  COLUMNS = %w[ KODS STATUSS STD ATRIB DAT_MOD DD_N DD_E ].freeze
  STATUSES = { "EKS" => "existing", "DEL" => "deleted", "ERR" => "erroneous" }.freeze
  FIELDS = %i[ code full_address postal_code latitude longitude status register_updated_on ].freeze

  Result = Data.define(:added, :updated, :marked, :skipped) do
    def to_s = "#{added} added, #{updated} updated, #{marked} marked deleted or erroneous, #{skipped} skipped"
  end

  class MissingColumns < StandardError; end

  def initialize(file, city: "Rīga")
    @file = file
    @city = city
  end

  def call
    check_columns
    known = Address.pluck(*FIELDS).to_h { |values| [ values.first, FIELDS.zip(values).to_h ] }
    additions, changes, counts = sort_rows(known)
    Address.transaction do
      additions.each_slice(1000) { |batch| Address.insert_all!(batch) }
      changes.each_slice(1000) { |batch| Address.upsert_all(batch, unique_by: :code) }
    end
    Result.new(added: additions.size, **counts)
  end

  private

  def check_columns
    headers = CSV.open(@file, headers: true, encoding: "bom|utf-8") { |csv| csv.shift&.headers.to_a }
    missing = COLUMNS - headers
    raise MissingColumns, "Missing columns: #{missing.join(', ')}" if missing.any?
  end

  def sort_rows(known)
    additions, changes = [], []
    counts = { updated: 0, marked: 0, skipped: 0 }
    each_city_row do |attributes|
      old = known[attributes[:code]]
      if old.nil?
        valid?(attributes) ? additions << attributes : counts[:skipped] += 1
      else
        attributes = attributes.merge(old.slice(:latitude, :longitude)) unless coordinates?(attributes)
        next if attributes == old

        counts[marked?(old, attributes) ? :marked : :updated] += 1
        changes << attributes
      end
    end
    [ additions, changes, counts ]
  end

  def each_city_row
    CSV.foreach(@file, headers: true, encoding: "bom|utf-8") do |row|
      next unless row["STD"].to_s.split(", ").include?(@city)

      yield code: row["KODS"].to_i, full_address: row["STD"], postal_code: row["ATRIB"].presence,
            latitude: decimal(row["DD_N"]), longitude: decimal(row["DD_E"]), status: STATUSES.fetch(row["STATUSS"]),
            register_updated_on: Date.strptime(row["DAT_MOD"], "%Y.%m.%d")
    end
  end

  def decimal(value) = value.presence && BigDecimal(value)

  def coordinates?(attributes) = attributes[:latitude] && attributes[:longitude]

  def valid?(attributes)
    coordinates?(attributes) && Address::CODES.cover?(attributes[:code]) &&
      Address::LATITUDES.cover?(attributes[:latitude]) && Address::LONGITUDES.cover?(attributes[:longitude])
  end

  def marked?(old, attributes)
    old[:status] != attributes[:status] && attributes[:status] != "existing"
  end
end
