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

  # FLT-07: up to 10 existing addresses whose street and house (the part
  # before the first comma, so not the city or the postal code) contain every
  # word of the text, regardless of letter case and Latvian diacritics. A word
  # equal to a whole word there (house 10, not 101) puts the address first;
  # the byte order of "C" keeps 214 before 214A on any database.
  def self.search(text)
    return none if text.to_s.strip.length < 3

    words = text.split.map { |word| sanitize_sql_like(word) }
    found = words.inject(existing) do |scope, word|
      scope.where("lower(unaccent(split_part(full_address, ', ', 1))) LIKE lower(unaccent(?))", "%#{word}%")
    end
    found.order(Arel.sql(whole_words(words))).order(Arel.sql('full_address COLLATE "C"')).limit(10)
  end

  def self.whole_words(words)
    words.map do |word|
      sanitize_sql_array([ "(CASE WHEN ' ' || lower(unaccent(split_part(full_address, ', ', 1))) || ' ' " \
                           "LIKE lower(unaccent(?)) THEN 0 ELSE 1 END)", "% #{word} %" ])
    end.join(" + ")
  end
  private_class_method :whole_words
end
