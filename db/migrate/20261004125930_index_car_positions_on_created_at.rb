# TRK-05: the nightly deletion and the tracking page read positions by the
# day they came. Nothing reads them by the phone's time alone any more: the
# map and the SOS go through the index of a car and that time.
class IndexCarPositionsOnCreatedAt < ActiveRecord::Migration[8.1]
  def change
    add_index :car_positions, :created_at
    remove_index :car_positions, :recorded_at
  end
end
