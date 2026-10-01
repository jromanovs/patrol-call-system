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

  def label = "#{name} · #{contract_number}"

  private

  def address_existing
    errors.add(:address, "is not an existing address in the register") if address && !address.existing?
  end
end
