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

ActiveRecord::Schema[8.1].define(version: 2026_05_25_231848) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "buildings", force: :cascade do |t|
    t.string "abbreviation", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["abbreviation"], name: "index_buildings_on_abbreviation", unique: true
    t.index ["name"], name: "index_buildings_on_name", unique: true
    t.check_constraint "length(TRIM(BOTH FROM abbreviation)) > 0 AND length(TRIM(BOTH FROM name)) > 0", name: "buildings_abbreviation_and_name_not_blank"
  end

  create_table "course_meeting_times", force: :cascade do |t|
    t.integer "begin_time", null: false
    t.bigint "course_id", null: false
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.datetime "end_date", null: false
    t.integer "end_time", null: false
    t.integer "hours_week"
    t.integer "meeting_schedule_type", null: false
    t.integer "meeting_type", null: false
    t.bigint "room_id", null: false
    t.datetime "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_course_meeting_times_on_course_id"
    t.index ["day_of_week"], name: "index_course_meeting_times_on_day_of_week"
    t.index ["room_id"], name: "index_course_meeting_times_on_room_id"
    t.check_constraint "begin_time >= 0 AND begin_time <= 2359", name: "course_meeting_times_begin_time_range"
    t.check_constraint "day_of_week >= 0 AND day_of_week <= 6", name: "course_meeting_times_day_of_week_range"
    t.check_constraint "end_date >= start_date", name: "course_meeting_times_end_date_on_or_after_start_date"
    t.check_constraint "end_time >= 0 AND end_time <= 2359", name: "course_meeting_times_end_time_range"
    t.check_constraint "end_time >= begin_time", name: "course_meeting_times_end_after_begin"
    t.check_constraint "meeting_schedule_type = ANY (ARRAY[1, 2])", name: "course_meeting_times_schedule_type_valid"
    t.check_constraint "meeting_type = 1", name: "course_meeting_times_meeting_type_valid"
  end

  create_table "courses", force: :cascade do |t|
    t.integer "course_number", null: false
    t.datetime "created_at", null: false
    t.integer "credit_hours"
    t.integer "crn", null: false
    t.date "end_date", null: false
    t.string "grade_mode"
    t.string "schedule_type", null: false
    t.integer "seats_available"
    t.integer "seats_capacity"
    t.string "section_number", null: false
    t.date "start_date", null: false
    t.string "status", default: "active", null: false
    t.string "subject", null: false
    t.bigint "term_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["crn", "term_id"], name: "index_courses_on_crn_and_term_id", unique: true
    t.index ["status"], name: "index_courses_on_status"
    t.index ["term_id"], name: "index_courses_on_term_id"
    t.check_constraint "credit_hours IS NULL OR credit_hours > 0", name: "courses_credit_hours_positive"
    t.check_constraint "schedule_type::text = ANY (ARRAY['EXT'::character varying, 'HYB'::character varying, 'IND'::character varying, 'LAB'::character varying, 'LEC'::character varying, 'ONL'::character varying, 'ONB'::character varying, 'OLB'::character varying, 'OLC'::character varying, 'RLB'::character varying, 'RLC'::character varying, 'SAB'::character varying]::text[])", name: "courses_schedule_type_valid"
    t.check_constraint "seats_available IS NULL OR seats_available >= 0", name: "courses_seats_available_non_negative"
    t.check_constraint "seats_available IS NULL OR seats_capacity IS NULL OR seats_available <= seats_capacity", name: "courses_seats_available_le_capacity"
    t.check_constraint "seats_capacity IS NULL OR seats_capacity >= 0", name: "courses_seats_capacity_non_negative"
    t.check_constraint "start_date IS NULL OR end_date IS NULL OR end_date >= start_date", name: "courses_end_date_on_or_after_start_date"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'cancelled'::character varying]::text[])", name: "courses_status_valid"
  end

  create_table "enrollments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rooms", force: :cascade do |t|
    t.bigint "building_id", null: false
    t.datetime "created_at", null: false
    t.integer "floor", null: false
    t.string "number", null: false
    t.datetime "updated_at", null: false
    t.index ["building_id", "number"], name: "index_rooms_on_building_id_and_number", unique: true
    t.index ["building_id"], name: "index_rooms_on_building_id"
    t.check_constraint "SUBSTRING(number FROM 1 FOR 1) = floor::text", name: "rooms_floor_matches_number_prefix"
    t.check_constraint "floor >= 0", name: "rooms_floor_non_negative"
  end

  create_table "terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "season", null: false
    t.integer "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["uid"], name: "index_terms_on_uid", unique: true
    t.index ["year", "season"], name: "index_terms_on_year_and_season", unique: true
    t.check_constraint "season = ANY (ARRAY[1, 2, 3])", name: "terms_season_valid"
    t.check_constraint "year >= 2012", name: "terms_year_not_before_first_term"
  end

  create_table "twenty_five_live_event_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "defn_state", default: 1, null: false
    t.string "name", null: false
    t.integer "sort_order"
    t.integer "twenty_five_live_id", null: false
    t.datetime "updated_at", null: false
    t.index ["twenty_five_live_id"], name: "index_twenty_five_live_event_categories_on_twenty_five_live_id", unique: true
  end

  create_table "twenty_five_live_event_custom_attributes", force: :cascade do |t|
    t.string "attribute_type"
    t.string "attribute_type_name"
    t.datetime "created_at", null: false
    t.integer "defn_state", default: 1, null: false
    t.string "multi_val"
    t.string "name", null: false
    t.integer "sort_order"
    t.integer "twenty_five_live_id", null: false
    t.datetime "updated_at", null: false
    t.index ["twenty_five_live_id"], name: "idx_on_twenty_five_live_id_bd51b01498", unique: true
  end

  create_table "twenty_five_live_organizations", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "organization_type_name"
    t.integer "twenty_five_live_id", null: false
    t.datetime "updated_at", null: false
    t.index ["twenty_five_live_id"], name: "index_twenty_five_live_organizations_on_twenty_five_live_id", unique: true
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0", name: "twenty_five_live_organizations_name_not_blank"
  end

  create_table "twenty_five_live_resources", force: :cascade do |t|
    t.string "assign_perm"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "schedule_perm"
    t.integer "stock_level"
    t.integer "twenty_five_live_id", null: false
    t.datetime "updated_at", null: false
    t.index ["twenty_five_live_id"], name: "index_twenty_five_live_resources_on_twenty_five_live_id", unique: true
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0", name: "twenty_five_live_resources_name_not_blank"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "course_meeting_times", "courses"
  add_foreign_key "course_meeting_times", "rooms"
  add_foreign_key "courses", "terms"
  add_foreign_key "rooms", "buildings"
end
