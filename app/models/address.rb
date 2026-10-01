# An address from the State Address Register (2.4). Records come from the
# register file and are never edited by users.
class Address < ApplicationRecord
  has_many :guarded_sites, dependent: :restrict_with_error

  enum :status, { existing: 0, deleted: 1, erroneous: 2 }, validate: true

  validates :code, uniqueness: true, numericality: { only_integer: true, in: 100_000_000..999_999_999 }
  validates :full_address, presence: true
  validates :postal_code, format: { with: /\ALV-\d{4}\z/ }, allow_blank: true
  validates :latitude, numericality: { in: 55.6..58.1 }
  validates :longitude, numericality: { in: 20.9..28.3 }
  validates :register_updated_on, presence: true
end
