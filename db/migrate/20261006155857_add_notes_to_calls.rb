# UPD-09, UPD-10: the note of a closing and the reason of a cancellation, kept
# apart from the description. Until now each was written into the description
# after the text that stood there, under an English name; those lines are
# moved here, and put back as they were on the way down.
class AddNotesToCalls < ActiveRecord::Migration[8.1]
  # The column, the name the line began with, and the status of the call
  # whose step wrote it (closed, cancelled).
  LINES = [ [ :closing_note, "Closing note", 3 ], [ :cancellation_reason, "Cancelled", 4 ] ].freeze

  def up
    add_column :calls, :closing_note, :text
    add_column :calls, :cancellation_reason, :text
    move
  end

  def down
    put_back
    remove_column :calls, :cancellation_reason
    remove_column :calls, :closing_note
  end

  # A step wrote its line last, so the line runs to the end of the text.
  def move
    LINES.each do |column, name, status|
      execute(<<~SQL.squish)
        UPDATE calls
        SET #{column} = substring(description from '(?:^|\\n)#{name}: (.*)$'),
            description = NULLIF(regexp_replace(description, '(?:^|\\n)#{name}: .*$', ''), '')
        WHERE status = #{status} AND description ~ '(?:^|\\n)#{name}: '
      SQL
    end
  end

  def put_back
    LINES.each do |column, name, _status|
      execute(<<~SQL.squish)
        UPDATE calls
        SET description = concat_ws(E'\\n', NULLIF(description, ''), '#{name}: ' || #{column}), #{column} = NULL
        WHERE #{column} IS NOT NULL
      SQL
    end
  end
end
