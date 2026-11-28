# The tables of solid_errors 0.9.1 in the primary database: its README moves
# the schema of its own database (db/errors_schema.rb of the gem) into a
# migration when the errors share the database of the application.
class CreateSolidErrorsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_errors do |t|
      t.text :exception_class, null: false
      t.text :message, null: false
      t.text :severity, null: false
      t.text :source
      t.datetime :resolved_at
      t.string :fingerprint, limit: 64, null: false
      t.timestamps
      t.index :fingerprint, unique: true
      t.index :resolved_at
    end

    create_table :solid_errors_occurrences do |t|
      t.references :error, null: false, foreign_key: { to_table: :solid_errors }
      t.text :backtrace
      t.json :context
      t.timestamps
    end
  end
end
