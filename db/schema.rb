# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_01_210813) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "unaccent"

  create_table "addresses", force: :cascade do |t|
    t.integer "code", null: false
    t.datetime "created_at", null: false
    t.string "full_address", null: false
    t.decimal "latitude", precision: 8, scale: 6, null: false
    t.decimal "longitude", precision: 8, scale: 6, null: false
    t.string "postal_code"
    t.date "register_updated_on", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_addresses_on_code", unique: true
  end

  create_table "calls", force: :cascade do |t|
    t.integer "alarm_type"
    t.datetime "arrived_at"
    t.string "caller_name"
    t.string "caller_phone"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "dispatched_at"
    t.bigint "dispatched_by_id"
    t.bigint "guarded_site_id", null: false
    t.integer "outcome"
    t.bigint "patrol_car_id"
    t.integer "priority", null: false
    t.datetime "received_at", null: false
    t.bigint "registered_by_id", null: false
    t.integer "sensor_zone"
    t.integer "status", default: 0, null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["dispatched_by_id"], name: "index_calls_on_dispatched_by_id"
    t.index ["guarded_site_id"], name: "index_calls_on_guarded_site_id"
    t.index ["patrol_car_id"], name: "index_calls_on_active_patrol_car", unique: true, where: "(status = ANY (ARRAY[1, 2]))"
    t.index ["patrol_car_id"], name: "index_calls_on_patrol_car_id"
    t.index ["registered_by_id"], name: "index_calls_on_registered_by_id"
    t.index ["status"], name: "index_calls_on_status"
  end

  create_table "guarded_sites", force: :cascade do |t|
    t.text "access_notes"
    t.bigint "address_id", null: false
    t.string "client_name", null: false
    t.string "contract_number", null: false
    t.date "contract_start_date", null: false
    t.integer "contract_status", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "district", null: false
    t.string "keyholder_phone", null: false
    t.string "name", null: false
    t.integer "site_type", null: false
    t.datetime "updated_at", null: false
    t.index "lower((contract_number)::text)", name: "index_guarded_sites_on_lower_contract_number", unique: true
    t.index ["address_id"], name: "index_guarded_sites_on_address_id"
  end

  create_table "patrol_cars", force: :cascade do |t|
    t.string "call_sign", null: false
    t.datetime "created_at", null: false
    t.integer "crew_size", null: false
    t.integer "district", null: false
    t.string "model", null: false
    t.string "plate_number", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["call_sign"], name: "index_patrol_cars_on_call_sign", unique: true
    t.index ["plate_number"], name: "index_patrol_cars_on_plate_number", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "google_uid"
    t.datetime "last_signed_in_at"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
  end

  add_foreign_key "calls", "guarded_sites"
  add_foreign_key "calls", "patrol_cars"
  add_foreign_key "calls", "users", column: "dispatched_by_id"
  add_foreign_key "calls", "users", column: "registered_by_id"
  add_foreign_key "guarded_sites", "addresses"
  add_foreign_key "sessions", "users"
end
