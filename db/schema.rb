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

ActiveRecord::Schema[7.2].define(version: 2025_03_20_090100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "restaurant_id", null: false
    t.text "description"
    t.index ["restaurant_id"], name: "index_categories_on_restaurant_id"
  end

  create_table "inventory_statuses", force: :cascade do |t|
    t.bigint "menu_item_id", null: false
    t.integer "quantity", default: 0
    t.boolean "in_stock", default: true
    t.boolean "low_stock", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id"], name: "index_inventory_statuses_on_menu_item_id"
  end

  create_table "layouts", force: :cascade do |t|
    t.string "name"
    t.bigint "restaurant_id", null: false
    t.jsonb "sections_data", default: {"sections"=>[]}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_layouts_on_restaurant_id"
  end

  create_table "menu_item_categories", force: :cascade do |t|
    t.bigint "menu_item_id", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_menu_item_categories_on_category_id"
    t.index ["menu_item_id", "category_id"], name: "index_menu_item_categories_on_menu_item_id_and_category_id", unique: true
    t.index ["menu_item_id"], name: "index_menu_item_categories_on_menu_item_id"
  end

  create_table "menu_item_stock_audits", force: :cascade do |t|
    t.bigint "menu_item_id", null: false
    t.integer "previous_quantity", null: false
    t.integer "new_quantity", null: false
    t.string "reason"
    t.bigint "user_id"
    t.bigint "order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_menu_item_stock_audits_on_created_at"
    t.index ["menu_item_id"], name: "index_menu_item_stock_audits_on_menu_item_id"
    t.index ["order_id"], name: "index_menu_item_stock_audits_on_order_id"
    t.index ["user_id"], name: "index_menu_item_stock_audits_on_user_id"
  end

  create_table "menu_items", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.decimal "price", precision: 8, scale: 2, default: "0.0"
    t.boolean "available", default: true
    t.bigint "menu_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_url"
    t.string "category"
    t.integer "advance_notice_hours", default: 0, null: false
    t.boolean "seasonal", default: false, null: false
    t.date "available_from"
    t.date "available_until"
    t.string "promo_label"
    t.boolean "featured"
    t.integer "stock_status"
    t.text "status_note"
    t.decimal "cost_to_make", precision: 8, scale: 2, default: "0.0"
    t.boolean "enable_stock_tracking", default: false
    t.integer "stock_quantity"
    t.integer "damaged_quantity", default: 0
    t.integer "low_stock_threshold", default: 10
    t.jsonb "available_days", default: []
    t.index ["menu_id", "available"], name: "index_menu_items_on_menu_id_and_available"
    t.index ["menu_id", "category"], name: "index_menu_items_on_menu_id_and_category"
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

  create_table "merchandise_collections", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: false
    t.bigint "restaurant_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id", "active"], name: "index_merchandise_collections_on_restaurant_id_and_active"
    t.index ["restaurant_id"], name: "index_merchandise_collections_on_restaurant_id"
  end

  create_table "merchandise_items", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.decimal "base_price", precision: 8, scale: 2, default: "0.0"
    t.string "image_url"
    t.boolean "available", default: true
    t.integer "stock_status", default: 0
    t.text "status_note"
    t.bigint "merchandise_collection_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "additional_images", default: "[]"
    t.integer "low_stock_threshold", default: 5
    t.string "second_image_url"
    t.index ["merchandise_collection_id", "available"], name: "idx_on_merchandise_collection_id_available_397f61ae61"
    t.index ["merchandise_collection_id"], name: "index_merchandise_items_on_merchandise_collection_id"
  end

  create_table "merchandise_variants", force: :cascade do |t|
    t.bigint "merchandise_item_id", null: false
    t.string "size"
    t.string "color"
    t.string "sku"
    t.decimal "price_adjustment", precision: 8, scale: 2, default: "0.0"
    t.integer "stock_quantity", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "low_stock_threshold", default: 5
    t.index ["merchandise_item_id", "size", "color"], name: "index_merch_variants_on_item_size_color"
    t.index ["merchandise_item_id"], name: "index_merchandise_variants_on_merchandise_item_id"
    t.index ["stock_quantity"], name: "index_merchandise_variants_on_stock_quantity"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "notification_type"
    t.string "delivery_method"
    t.datetime "scheduled_for"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "resource_type"
    t.bigint "resource_id"
    t.bigint "restaurant_id"
    t.string "title"
    t.text "body"
    t.boolean "acknowledged", default: false
    t.datetime "acknowledged_at"
    t.bigint "acknowledged_by_id"
    t.index ["acknowledged", "notification_type", "restaurant_id"], name: "idx_notifications_filter"
    t.index ["acknowledged_by_id"], name: "index_notifications_on_acknowledged_by_id"
    t.index ["resource_type", "resource_id"], name: "index_notifications_on_resource"
    t.index ["restaurant_id"], name: "index_notifications_on_restaurant_id"
  end

  create_table "operating_hours", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.integer "day_of_week", null: false
    t.time "open_time"
    t.time "close_time"
    t.boolean "closed", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id", "day_of_week"], name: "index_operating_hours_on_restaurant_id_and_day_of_week", unique: true
    t.index ["restaurant_id"], name: "index_operating_hours_on_restaurant_id"
  end

  create_table "option_groups", force: :cascade do |t|
    t.string "name", null: false
    t.integer "min_select", default: 0
    t.integer "max_select", default: 1
    t.bigint "menu_item_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "free_option_count", default: 0, null: false
    t.index ["menu_item_id"], name: "index_option_groups_on_menu_item_id"
  end

  create_table "options", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "additional_price", precision: 8, scale: 2, default: "0.0"
    t.boolean "available", default: true
    t.bigint "option_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_preselected", default: false, null: false
    t.index ["option_group_id"], name: "index_options_on_option_group_id"
  end

  create_table "order_acknowledgments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "user_id", null: false
    t.datetime "acknowledged_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_at"], name: "index_order_acknowledgments_on_acknowledged_at"
    t.index ["order_id", "user_id"], name: "index_order_acknowledgments_on_order_id_and_user_id", unique: true
    t.index ["order_id"], name: "index_order_acknowledgments_on_order_id"
    t.index ["user_id"], name: "index_order_acknowledgments_on_user_id"
  end

  create_table "order_payments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "payment_type", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "payment_method"
    t.string "transaction_id"
    t.string "payment_id"
    t.jsonb "payment_details"
    t.string "status"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "refunded_items"
    t.index ["order_id"], name: "index_order_payments_on_order_id"
    t.index ["payment_id"], name: "index_order_payments_on_payment_id"
    t.index ["transaction_id"], name: "index_order_payments_on_transaction_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.bigint "user_id"
    t.jsonb "items", default: []
    t.string "status", default: "pending", null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.string "promo_code"
    t.text "special_instructions"
    t.datetime "estimated_pickup_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contact_name"
    t.string "contact_phone"
    t.string "contact_email"
    t.string "payment_method"
    t.string "transaction_id"
    t.string "payment_status", default: "pending"
    t.decimal "payment_amount", precision: 10, scale: 2
    t.string "vip_code"
    t.bigint "vip_access_code_id"
    t.jsonb "merchandise_items", default: []
    t.decimal "refund_amount", precision: 10, scale: 2
    t.string "dispute_reason"
    t.string "payment_id"
    t.index ["payment_id"], name: "index_orders_on_payment_id"
    t.index ["restaurant_id", "status"], name: "index_orders_on_restaurant_id_and_status"
    t.index ["restaurant_id"], name: "index_orders_on_restaurant_id"
    t.index ["user_id", "created_at"], name: "index_orders_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.index ["vip_access_code_id"], name: "index_orders_on_vip_access_code_id"
  end

  create_table "promo_codes", force: :cascade do |t|
    t.string "code", null: false
    t.integer "discount_percent", default: 0, null: false
    t.datetime "valid_from", default: -> { "now()" }, null: false
    t.datetime "valid_until"
    t.integer "max_uses"
    t.integer "current_uses", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "restaurant_id", null: false
    t.index ["code"], name: "index_promo_codes_on_code", unique: true
    t.index ["restaurant_id"], name: "index_promo_codes_on_restaurant_id"
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
    t.integer "duration_minutes", default: 60
    t.index ["restaurant_id"], name: "index_reservations_on_restaurant_id"
    t.check_constraint "status::text = ANY (ARRAY['booked'::character varying::text, 'reserved'::character varying::text, 'seated'::character varying::text, 'finished'::character varying::text, 'canceled'::character varying::text, 'no_show'::character varying::text])", name: "check_reservation_status"
  end

  create_table "restaurants", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.string "layout_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "current_layout_id"
    t.integer "time_slot_interval", default: 30
    t.string "time_zone", default: "Pacific/Guam", null: false
    t.integer "default_reservation_length", default: 60, null: false
    t.jsonb "admin_settings", default: {}, null: false
    t.string "allowed_origins", default: [], array: true
    t.string "phone_number"
    t.bigint "current_menu_id"
    t.bigint "current_event_id"
    t.boolean "vip_enabled", default: false
    t.string "code_prefix"
    t.bigint "current_merchandise_collection_id"
    t.string "contact_email"
    t.string "custom_pickup_location"
    t.string "facebook_url"
    t.string "instagram_url"
    t.string "twitter_url"
    t.index ["current_event_id"], name: "index_restaurants_on_current_event_id"
    t.index ["current_layout_id"], name: "index_restaurants_on_current_layout_id"
    t.index ["current_menu_id"], name: "index_restaurants_on_current_menu_id"
    t.index ["current_merchandise_collection_id"], name: "index_restaurants_on_current_merchandise_collection_id"
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

  create_table "site_settings", force: :cascade do |t|
    t.string "hero_image_url"
    t.string "spinner_image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "special_events", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.date "event_date", null: false
    t.boolean "exclusive_booking", default: false
    t.integer "max_capacity", default: 0
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "closed", default: false
    t.time "start_time"
    t.time "end_time"
    t.boolean "vip_only_checkout", default: false
    t.string "code_prefix"
    t.index ["restaurant_id", "event_date"], name: "index_special_events_on_restaurant_id_and_event_date", unique: true
    t.index ["restaurant_id"], name: "index_special_events_on_restaurant_id"
  end

  create_table "store_credits", force: :cascade do |t|
    t.bigint "order_id"
    t.string "customer_email", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "reason"
    t.string "status", default: "active"
    t.datetime "expires_at", precision: nil
    t.decimal "remaining_amount", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_email"], name: "index_store_credits_on_customer_email"
    t.index ["order_id"], name: "index_store_credits_on_order_id"
    t.index ["status"], name: "index_store_credits_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "customer"
    t.bigint "restaurant_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.boolean "phone_verified", default: false
    t.string "verification_code"
    t.datetime "verification_code_sent_at"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["phone"], name: "index_users_on_phone_not_null", where: "(phone IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["restaurant_id"], name: "index_users_on_restaurant_id"
  end

  create_table "vip_access_codes", force: :cascade do |t|
    t.bigint "restaurant_id", null: false
    t.bigint "special_event_id"
    t.string "code", null: false
    t.string "name"
    t.integer "max_uses"
    t.integer "current_uses", default: 0
    t.datetime "expires_at"
    t.boolean "is_active", default: true
    t.bigint "user_id"
    t.string "group_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "archived", default: false
    t.string "recipient_email"
    t.index ["archived"], name: "index_vip_access_codes_on_archived"
    t.index ["code", "restaurant_id"], name: "index_vip_access_codes_on_code_and_restaurant_id", unique: true
    t.index ["restaurant_id"], name: "index_vip_access_codes_on_restaurant_id"
    t.index ["special_event_id"], name: "index_vip_access_codes_on_special_event_id"
    t.index ["user_id"], name: "index_vip_access_codes_on_user_id"
  end

  create_table "vip_code_recipients", force: :cascade do |t|
    t.bigint "vip_access_code_id", null: false
    t.string "email"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_vip_code_recipients_on_email"
    t.index ["vip_access_code_id", "email"], name: "index_vip_code_recipients_on_vip_access_code_id_and_email"
    t.index ["vip_access_code_id"], name: "index_vip_code_recipients_on_vip_access_code_id"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "categories", "restaurants"
  add_foreign_key "inventory_statuses", "menu_items"
  add_foreign_key "layouts", "restaurants"
  add_foreign_key "menu_item_categories", "categories"
  add_foreign_key "menu_item_categories", "menu_items"
  add_foreign_key "menu_item_stock_audits", "menu_items"
  add_foreign_key "menu_item_stock_audits", "orders"
  add_foreign_key "menu_item_stock_audits", "users"
  add_foreign_key "menu_items", "menus"
  add_foreign_key "menus", "restaurants"
  add_foreign_key "merchandise_collections", "restaurants"
  add_foreign_key "merchandise_items", "merchandise_collections"
  add_foreign_key "merchandise_variants", "merchandise_items"
  add_foreign_key "notifications", "restaurants"
  add_foreign_key "notifications", "users", column: "acknowledged_by_id"
  add_foreign_key "operating_hours", "restaurants"
  add_foreign_key "option_groups", "menu_items"
  add_foreign_key "options", "option_groups"
  add_foreign_key "order_acknowledgments", "orders"
  add_foreign_key "order_acknowledgments", "users"
  add_foreign_key "order_payments", "orders"
  add_foreign_key "orders", "restaurants"
  add_foreign_key "orders", "users"
  add_foreign_key "orders", "vip_access_codes"
  add_foreign_key "promo_codes", "restaurants"
  add_foreign_key "reservations", "restaurants"
  add_foreign_key "restaurants", "layouts", column: "current_layout_id", on_delete: :nullify
  add_foreign_key "restaurants", "menus", column: "current_menu_id"
  add_foreign_key "restaurants", "merchandise_collections", column: "current_merchandise_collection_id"
  add_foreign_key "restaurants", "special_events", column: "current_event_id"
  add_foreign_key "seat_allocations", "reservations"
  add_foreign_key "seat_allocations", "seats"
  add_foreign_key "seat_allocations", "waitlist_entries"
  add_foreign_key "seat_sections", "layouts"
  add_foreign_key "seats", "seat_sections"
  add_foreign_key "special_events", "restaurants"
  add_foreign_key "users", "restaurants"
  add_foreign_key "vip_access_codes", "restaurants"
  add_foreign_key "vip_access_codes", "special_events"
  add_foreign_key "vip_access_codes", "users"
  add_foreign_key "vip_code_recipients", "vip_access_codes"
  add_foreign_key "waitlist_entries", "restaurants"
end
