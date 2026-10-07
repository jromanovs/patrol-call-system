# BR-20: the source of positions is chosen for each car, and each position is
# kept with its source named. The switch of tracking for all cars and the
# source a position took by default served the version before that choice,
# which is no longer among the versions the server can go back to.
class DropCarTrackingFromSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :settings, :car_tracking, :boolean, null: false, default: false
    change_column_default :car_positions, :source, from: 1, to: nil
  end
end
