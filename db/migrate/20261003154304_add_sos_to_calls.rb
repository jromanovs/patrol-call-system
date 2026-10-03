# BR-21: a crew's SOS is a call without a site and, sent by a phone, without
# a registering user; it keeps the car that raised it, the place of its last
# signal, the count of its signals and who acknowledged it. A car has one
# active SOS at a time. STO-04: the database still refuses any other call
# without a site or a registering user, and an SOS without its car, place
# or signals.
class AddSosToCalls < ActiveRecord::Migration[8.1]
  ACTIVE = "status IN (0, 1, 2, 5)".freeze
  SITE = "type = 'SosCall' OR (guarded_site_id IS NOT NULL AND registered_by_id IS NOT NULL)".freeze
  PLACE = "type <> 'SosCall' OR (raised_by_id IS NOT NULL AND latitude IS NOT NULL AND longitude IS NOT NULL " \
          "AND signals IS NOT NULL AND signalled_at IS NOT NULL)".freeze

  def change
    change_column_null :calls, :guarded_site_id, true
    change_column_null :calls, :registered_by_id, true
    add_place
    add_signals
    add_reference :calls, :raised_by, foreign_key: { to_table: :patrol_cars }, index: false
    add_reference :calls, :acknowledged_by, foreign_key: { to_table: :users }
    add_index :calls, :raised_by_id, unique: true, where: ACTIVE, name: "index_calls_on_active_raised_by"
    add_check_constraint :calls, SITE, name: "calls_site"
    add_check_constraint :calls, PLACE, name: "calls_sos_place"
  end

  private

  def add_place
    add_column :calls, :latitude, :decimal, precision: 9, scale: 6
    add_column :calls, :longitude, :decimal, precision: 9, scale: 6
    add_column :calls, :accuracy, :integer
  end

  def add_signals
    add_column :calls, :signals, :integer
    add_column :calls, :signalled_at, :datetime
    add_column :calls, :acknowledged_at, :datetime
  end
end
