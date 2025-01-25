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

ActiveRecord::Schema[7.2].define(version: 2025_01_24_231116) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "layouts", force: :cascade do |t|
    t.string "name"
    t.bigint "restaurant_id", null: false
    t.jsonb "sections_data", default: {"sections"=>[]}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_layouts_on_restaurant_id"
  end

  create_table "menu_items", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.decimal "price", precision: 8, scale: 2, default: "0.0"
    t.boolean "available", default: true
    t.bigint "menu_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_id"], name: "index_menu_items_on_menu_id"
  end

  create_table "menus", force: :cascade do |t|
    t.string "name"
    t.boolean "active"
    t.bigint "restaurant_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_menus_on_restaurant_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.string "notification_type"
    t.string "delivery_method"
    t.datetime "scheduled_for"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reservation_id"], name: "index_notifications_on_reservation_id"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.datetime "start_time"
    t.datetime "end_time"
    t.integer "party_size", default: 1
    t.string "contact_name"
    t.string "contact_phone"
    t.string "contact_email"
    t.decimal "deposit_amount"
    t.string "reservation_source", default: "online"
    t.text "special_requests"
    t.string "status", default: "booked"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "seat_preferences", default: [], null: false
    t.index ["restaurant_id"], name: "index_reservations_on_restaurant_id"
    t.check_constraint "status::text = ANY (ARRAY['booked'::character varying, 'reserved'::character varying, 'seated'::character varying, 'finished'::character varying, 'canceled'::character varying, 'no_show'::character varying]::text[])", name: "check_reservation_status"
  end

  create_table "restaurants", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.string "opening_hours"
    t.string "layout_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "current_layout_id"
    t.time "opening_time"
    t.time "closing_time"
    t.integer "time_slot_interval", default: 30
    t.string "time_zone", default: "Pacific/Guam", null: false
    t.index ["current_layout_id"], name: "index_restaurants_on_current_layout_id"
  end

  create_table "seat_allocations", force: :cascade do |t|
    t.bigint "reservation_id"
    t.bigint "seat_id", null: false
    t.datetime "start_time"
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "waitlist_entry_id"
    t.datetime "end_time"
    t.index ["reservation_id"], name: "index_seat_allocations_on_reservation_id"
    t.index ["seat_id"], name: "index_seat_allocations_on_seat_id"
    t.index ["waitlist_entry_id"], name: "index_seat_allocations_on_waitlist_entry_id"
  end

  create_table "seat_sections", force: :cascade do |t|
    t.string "name"
    t.string "section_type"
    t.string "orientation"
    t.integer "offset_x"
    t.integer "offset_y"
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "layout_id", null: false
    t.integer "floor_number", default: 1, null: false
    t.index ["layout_id"], name: "index_seat_sections_on_layout_id"
  end

  create_table "seats", force: :cascade do |t|
    t.string "label", null: false
    t.integer "position_x"
    t.integer "position_y"
    t.bigint "seat_section_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "capacity", default: 1, null: false
    t.index ["seat_section_id"], name: "index_seats_on_seat_section_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "staff"
    t.bigint "restaurant_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.index ["restaurant_id"], name: "index_users_on_restaurant_id"
  end

  create_table "waitlist_entries", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.string "contact_name"
    t.integer "party_size"
    t.datetime "check_in_time"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_waitlist_entries_on_restaurant_id"
  end

  add_foreign_key "layouts", "restaurants"
  add_foreign_key "menu_items", "menus"
  add_foreign_key "menus", "restaurants"
  add_foreign_key "notifications", "reservations"
  add_foreign_key "reservations", "restaurants"
  add_foreign_key "restaurants", "layouts", column: "current_layout_id", on_delete: :nullify
  add_foreign_key "seat_allocations", "reservations"
  add_foreign_key "seat_allocations", "seats"
  add_foreign_key "seat_allocations", "waitlist_entries"
  add_foreign_key "seat_sections", "layouts"
  add_foreign_key "seats", "seat_sections"
  add_foreign_key "users", "restaurants"
  add_foreign_key "waitlist_entries", "restaurants"
end
