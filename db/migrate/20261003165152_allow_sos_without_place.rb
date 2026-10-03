# BR-21: a crew's SOS goes also when its phone gives no position. Its place
# is whole or absent, and has the time it was taken: earlier than the signal
# when it is the car's last kept position.
class AllowSosWithoutPlace < ActiveRecord::Migration[8.1]
  WAS = "type <> 'SosCall' OR (raised_by_id IS NOT NULL AND latitude IS NOT NULL AND longitude IS NOT NULL " \
        "AND signals IS NOT NULL AND signalled_at IS NOT NULL)".freeze
  NOW = "type <> 'SosCall' OR (raised_by_id IS NOT NULL AND signals IS NOT NULL AND signalled_at IS NOT NULL " \
        "AND (latitude IS NULL) = (longitude IS NULL))".freeze

  def change
    add_column :calls, :placed_at, :datetime
    reversible do |direction|
      direction.up { execute "UPDATE calls SET placed_at = signalled_at WHERE type = 'SosCall'" }
    end
    remove_check_constraint :calls, WAS, name: "calls_sos_place"
    add_check_constraint :calls, NOW, name: "calls_sos_place"
  end
end
