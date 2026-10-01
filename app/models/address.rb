# An address from the State Address Register (2.4). Records come from the
# register file and are never edited by users.
class Address < ApplicationRecord
  CODES = 100_000_000..999_999_999
  LATITUDES = 55.6..58.1
  LONGITUDES = 20.9..28.3

  has_many :guarded_sites, dependent: :restrict_with_error

  enum :status, { existing: 0, deleted: 1, erroneous: 2 }, validate: true

  validates :code, uniqueness: true, numericality: { only_integer: true, in: CODES }
  validates :full_address, presence: true
  validates :postal_code, format: { with: /\ALV-\d{4}\z/ }, allow_blank: true
  validates :latitude, numericality: { in: LATITUDES }
  validates :longitude, numericality: { in: LONGITUDES }
  validates :register_updated_on, presence: true

  # FLT-07: up to 10 existing addresses that contain every word of the text,
  # regardless of letter case and Latvian diacritics.
  def self.search(text)
    return none if text.to_s.strip.length < 3

    text.split.inject(existing) do |scope, word|
      scope.where("lower(unaccent(full_address)) LIKE lower(unaccent(?))", "%#{sanitize_sql_like(word)}%")
    end.order(:full_address).limit(10)
  end
end
