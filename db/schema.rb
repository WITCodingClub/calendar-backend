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

ActiveRecord::Schema[8.1].define(version: 2026_06_07_000019) do
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

  create_table "calendar_preferences", force: :cascade do |t|
    t.integer "color_id"
    t.datetime "created_at", null: false
    t.text "description_template"
    t.string "event_type"
    t.text "location_template"
    t.jsonb "reminder_settings"
    t.integer "scope", null: false
    t.text "title_template"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility"
    t.index ["user_id", "scope", "event_type"], name: "index_calendar_prefs_on_user_scope_type", unique: true
    t.index ["user_id"], name: "index_calendar_preferences_on_user_id"
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

  create_table "courses_faculties", id: false, force: :cascade do |t|
    t.bigint "course_id", null: false
    t.bigint "faculty_id", null: false
    t.index ["course_id", "faculty_id"], name: "index_courses_faculties_on_course_id_and_faculty_id", unique: true
    t.index ["course_id"], name: "index_courses_faculties_on_course_id"
    t.index ["faculty_id"], name: "index_courses_faculties_on_faculty_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["course_id"], name: "index_enrollments_on_course_id"
    t.index ["user_id", "course_id"], name: "index_enrollments_on_user_id_and_course_id", unique: true
    t.index ["user_id"], name: "index_enrollments_on_user_id"
  end

  create_table "event_preferences", force: :cascade do |t|
    t.integer "color_id"
    t.datetime "created_at", null: false
    t.text "description_template"
    t.text "location_template"
    t.bigint "preferenceable_id", null: false
    t.string "preferenceable_type", null: false
    t.jsonb "reminder_settings"
    t.text "title_template"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility"
    t.index ["preferenceable_type", "preferenceable_id"], name: "index_event_preferences_on_preferenceable"
    t.index ["user_id", "preferenceable_type", "preferenceable_id"], name: "index_event_prefs_on_user_and_preferenceable", unique: true
    t.index ["user_id"], name: "index_event_preferences_on_user_id"
  end

  create_table "faculties", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "department"
    t.datetime "directory_last_synced_at"
    t.jsonb "directory_raw_data"
    t.string "display_name"
    t.string "email", null: false
    t.string "employee_type"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "middle_name"
    t.string "office_location"
    t.string "phone"
    t.string "photo_url"
    t.string "rmp_id"
    t.jsonb "rmp_raw_data"
    t.string "school"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["department"], name: "index_faculties_on_department"
    t.index ["directory_last_synced_at"], name: "index_faculties_on_directory_last_synced_at"
    t.index ["directory_raw_data"], name: "index_faculties_on_directory_raw_data", using: :gin
    t.index ["email"], name: "index_faculties_on_email", unique: true
    t.index ["employee_type"], name: "index_faculties_on_employee_type"
    t.index ["rmp_id"], name: "index_faculties_on_rmp_id", unique: true
    t.index ["rmp_raw_data"], name: "index_faculties_on_rmp_raw_data", using: :gin
    t.index ["school"], name: "index_faculties_on_school"
  end

  create_table "final_exams", force: :cascade do |t|
    t.text "combined_crns"
    t.bigint "course_id"
    t.datetime "created_at", null: false
    t.integer "crn"
    t.integer "end_time", null: false
    t.date "exam_date", null: false
    t.string "location"
    t.text "notes"
    t.integer "start_time", null: false
    t.bigint "term_id", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_final_exams_on_course_id"
    t.index ["crn", "term_id"], name: "index_final_exams_on_crn_and_term_id", unique: true
    t.index ["term_id"], name: "index_final_exams_on_term_id"
  end

  create_table "friendships", force: :cascade do |t|
    t.bigint "addressee_id", null: false
    t.datetime "created_at", null: false
    t.bigint "requester_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["addressee_id", "status"], name: "index_friendships_on_addressee_id_and_status"
    t.index ["addressee_id"], name: "index_friendships_on_addressee_id"
    t.index ["requester_id", "addressee_id"], name: "index_friendships_on_requester_id_and_addressee_id", unique: true
    t.index ["requester_id", "status"], name: "index_friendships_on_requester_id_and_status"
    t.index ["requester_id"], name: "index_friendships_on_requester_id"
  end

  create_table "google_calendar_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time"
    t.string "event_data_hash"
    t.bigint "final_exam_id"
    t.bigint "google_calendar_id", null: false
    t.string "google_event_id", null: false
    t.datetime "last_synced_at"
    t.string "location"
    t.bigint "meeting_time_id"
    t.text "recurrence"
    t.datetime "start_time"
    t.string "summary"
    t.bigint "university_calendar_event_id"
    t.datetime "updated_at", null: false
    t.jsonb "user_edited_fields"
    t.index ["final_exam_id"], name: "index_google_calendar_events_on_final_exam_id"
    t.index ["google_calendar_id", "final_exam_id"], name: "idx_gcal_events_unique_final_exam", unique: true, where: "(final_exam_id IS NOT NULL)"
    t.index ["google_calendar_id", "meeting_time_id"], name: "idx_gcal_events_unique_meeting_time", unique: true, where: "(meeting_time_id IS NOT NULL)"
    t.index ["google_calendar_id", "meeting_time_id"], name: "idx_on_google_calendar_id_meeting_time_id"
    t.index ["google_calendar_id", "university_calendar_event_id"], name: "idx_gcal_events_unique_university", unique: true, where: "(university_calendar_event_id IS NOT NULL)"
    t.index ["google_calendar_id"], name: "index_google_calendar_events_on_google_calendar_id"
    t.index ["google_event_id"], name: "index_google_calendar_events_on_google_event_id"
    t.index ["last_synced_at"], name: "index_google_calendar_events_on_last_synced_at"
    t.index ["meeting_time_id"], name: "index_google_calendar_events_on_meeting_time_id"
    t.index ["university_calendar_event_id"], name: "index_google_calendar_events_on_university_calendar_event_id"
  end

  create_table "google_calendars", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "google_calendar_id", null: false
    t.datetime "last_synced_at"
    t.bigint "oauth_credential_id", null: false
    t.string "summary"
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.index ["google_calendar_id"], name: "index_google_calendars_on_google_calendar_id", unique: true
    t.index ["last_synced_at"], name: "index_google_calendars_on_last_synced_at"
    t.index ["oauth_credential_id"], name: "index_google_calendars_on_oauth_credential_id"
  end

  create_table "oauth_credentials", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.jsonb "metadata"
    t.string "provider", null: false
    t.string "refresh_token"
    t.datetime "token_expires_at"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_oauth_credentials_on_provider_and_uid", unique: true
    t.index ["token_expires_at"], name: "index_oauth_credentials_on_token_expires_at"
    t.index ["user_id", "provider", "email"], name: "index_oauth_credentials_on_user_provider_email", unique: true
    t.index ["user_id"], name: "index_oauth_credentials_on_user_id"
  end

  create_table "rating_distributions", force: :cascade do |t|
    t.decimal "avg_difficulty", precision: 3, scale: 2
    t.decimal "avg_rating", precision: 3, scale: 2
    t.datetime "created_at", null: false
    t.bigint "faculty_id", null: false
    t.integer "num_ratings", default: 0
    t.integer "r1", default: 0
    t.integer "r2", default: 0
    t.integer "r3", default: 0
    t.integer "r4", default: 0
    t.integer "r5", default: 0
    t.integer "total", default: 0
    t.datetime "updated_at", null: false
    t.decimal "would_take_again_percent", precision: 5, scale: 2
    t.index ["faculty_id"], name: "index_rating_distributions_on_faculty_id", unique: true
  end

  create_table "related_professors", force: :cascade do |t|
    t.decimal "avg_rating", precision: 3, scale: 2
    t.datetime "created_at", null: false
    t.bigint "faculty_id", null: false
    t.string "first_name"
    t.string "last_name"
    t.bigint "related_faculty_id"
    t.string "rmp_id", null: false
    t.datetime "updated_at", null: false
    t.index ["faculty_id", "rmp_id"], name: "index_related_professors_on_faculty_id_and_rmp_id", unique: true
    t.index ["faculty_id"], name: "index_related_professors_on_faculty_id"
    t.index ["related_faculty_id"], name: "index_related_professors_on_related_faculty_id"
  end

  create_table "rmp_ratings", force: :cascade do |t|
    t.string "attendance_mandatory"
    t.integer "clarity_rating"
    t.text "comment"
    t.string "course_name"
    t.datetime "created_at", null: false
    t.integer "difficulty_rating"
    t.bigint "faculty_id", null: false
    t.string "grade"
    t.integer "helpful_rating"
    t.boolean "is_for_credit"
    t.boolean "is_for_online_class"
    t.datetime "rating_date"
    t.string "rating_tags"
    t.string "rmp_id", null: false
    t.integer "thumbs_down_total", default: 0
    t.integer "thumbs_up_total", default: 0
    t.datetime "updated_at", null: false
    t.boolean "would_take_again"
    t.index ["faculty_id"], name: "index_rmp_ratings_on_faculty_id"
    t.index ["rmp_id"], name: "index_rmp_ratings_on_rmp_id", unique: true
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

  create_table "security_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.datetime "expires_at"
    t.string "google_subject", null: false
    t.string "jti", null: false
    t.bigint "oauth_credential_id"
    t.boolean "processed", default: false, null: false
    t.datetime "processed_at"
    t.text "processing_error"
    t.text "raw_event_data"
    t.string "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["event_type"], name: "index_security_events_on_event_type"
    t.index ["expires_at"], name: "index_security_events_on_expires_at"
    t.index ["jti"], name: "index_security_events_on_jti", unique: true
    t.index ["oauth_credential_id"], name: "index_security_events_on_oauth_credential_id"
    t.index ["processed"], name: "index_security_events_on_processed"
    t.index ["user_id"], name: "index_security_events_on_user_id"
  end

  create_table "teacher_rating_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "faculty_id", null: false
    t.integer "rmp_legacy_id", null: false
    t.integer "tag_count", default: 0
    t.string "tag_name", null: false
    t.datetime "updated_at", null: false
    t.index ["faculty_id", "rmp_legacy_id"], name: "index_teacher_rating_tags_on_faculty_id_and_rmp_legacy_id", unique: true
    t.index ["faculty_id"], name: "index_teacher_rating_tags_on_faculty_id"
  end

  create_table "terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "end_date"
    t.integer "season", null: false
    t.date "start_date"
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

  create_table "university_calendar_events", force: :cascade do |t|
    t.string "academic_term"
    t.boolean "all_day", default: false, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_time", null: false
    t.string "event_type_raw"
    t.string "ics_uid", null: false
    t.datetime "last_fetched_at"
    t.string "location"
    t.string "organization"
    t.text "recurrence"
    t.string "source_url"
    t.datetime "start_time", null: false
    t.text "summary", null: false
    t.bigint "term_id"
    t.datetime "updated_at", null: false
    t.index ["academic_term"], name: "index_university_calendar_events_on_academic_term"
    t.index ["category"], name: "index_university_calendar_events_on_category"
    t.index ["ics_uid"], name: "index_university_calendar_events_on_ics_uid", unique: true
    t.index ["start_time", "end_time"], name: "index_university_calendar_events_on_start_time_and_end_time"
    t.index ["term_id"], name: "index_university_calendar_events_on_term_id"
  end

  create_table "user_extension_configs", force: :cascade do |t|
    t.boolean "advanced_editing", default: false, null: false
    t.datetime "created_at", null: false
    t.string "default_color_lab", default: "#f6bf26", null: false
    t.string "default_color_lecture", default: "#039be5", null: false
    t.boolean "military_time", default: false, null: false
    t.boolean "sync_university_events", default: false, null: false
    t.jsonb "university_event_categories"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_user_extension_configs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "access_level", default: 0, null: false
    t.boolean "calendar_needs_sync", default: false, null: false
    t.string "calendar_token"
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
    t.datetime "last_calendar_sync_at"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.datetime "notifications_disabled_until"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["access_level"], name: "index_users_on_access_level"
    t.index ["calendar_needs_sync"], name: "index_users_on_calendar_needs_sync"
    t.index ["calendar_token"], name: "index_users_on_calendar_token", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_calendar_sync_at"], name: "index_users_on_last_calendar_sync_at"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "calendar_preferences", "users"
  add_foreign_key "course_meeting_times", "courses"
  add_foreign_key "course_meeting_times", "rooms"
  add_foreign_key "courses", "terms"
  add_foreign_key "enrollments", "courses"
  add_foreign_key "enrollments", "users"
  add_foreign_key "event_preferences", "users"
  add_foreign_key "final_exams", "courses"
  add_foreign_key "final_exams", "terms"
  add_foreign_key "friendships", "users", column: "addressee_id"
  add_foreign_key "friendships", "users", column: "requester_id"
  add_foreign_key "google_calendar_events", "course_meeting_times", column: "meeting_time_id"
  add_foreign_key "google_calendar_events", "google_calendars"
  add_foreign_key "google_calendars", "oauth_credentials"
  add_foreign_key "oauth_credentials", "users"
  add_foreign_key "rating_distributions", "faculties"
  add_foreign_key "related_professors", "faculties"
  add_foreign_key "related_professors", "faculties", column: "related_faculty_id"
  add_foreign_key "rmp_ratings", "faculties"
  add_foreign_key "rooms", "buildings"
  add_foreign_key "security_events", "oauth_credentials"
  add_foreign_key "security_events", "users"
  add_foreign_key "teacher_rating_tags", "faculties"
  add_foreign_key "university_calendar_events", "terms"
  add_foreign_key "user_extension_configs", "users"
end
