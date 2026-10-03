class AddAcceptedAtToCalls < ActiveRecord::Migration[8.1]
  def change
    # UPD-12, 2.10: when the crew accepted the call; the status accepted is a
    # new value of the integer status and needs no change of the column.
    add_column :calls, :accepted_at, :datetime
  end
end
