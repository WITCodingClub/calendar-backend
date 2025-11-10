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

ActiveRecord::Schema[8.1].define(version: 2025_11_10_033855) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "ahoy_clicks", force: :cascade do |t|
    t.string "campaign"
    t.string "token"
    t.index ["campaign"], name: "index_ahoy_clicks_on_campaign"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.bigint "user_id"
    t.bigint "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_messages", force: :cascade do |t|
    t.string "campaign"
    t.string "mailer"
    t.datetime "sent_at"
    t.text "subject"
    t.string "to_bidx"
    t.text "to_ciphertext"
    t.bigint "user_id"
    t.string "user_type"
    t.index ["campaign"], name: "index_ahoy_messages_on_campaign"
    t.index ["to_bidx"], name: "index_ahoy_messages_on_to_bidx"
    t.index ["user_type", "user_id"], name: "index_ahoy_messages_on_user"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.bigint "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "audits1984_audits", force: :cascade do |t|
    t.bigint "auditor_id", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "session_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["auditor_id"], name: "index_audits1984_audits_on_auditor_id"
    t.index ["session_id"], name: "index_audits1984_audits_on_session_id"
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.datetime "created_at"
    t.string "data_source"
    t.bigint "query_id"
    t.text "statement"
    t.bigint "user_id"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.string "check_type"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "emails"
    t.datetime "last_run_at"
    t.text "message"
    t.bigint "query_id"
    t.string "schedule"
    t.text "slack_channels"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dashboard_id"
    t.integer "position"
    t.bigint "query_id"
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "data_source"
    t.text "description"
    t.string "name"
    t.text "statement"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "buildings", force: :cascade do |t|
    t.string "abbreviation", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["abbreviation"], name: "index_buildings_on_abbreviation", unique: true
    t.index ["name"], name: "index_buildings_on_name", unique: true
  end

  create_table "calendar_preferences", force: :cascade do |t|
    t.integer "color_id"
    t.datetime "created_at", null: false
    t.text "description_template"
    t.string "event_type"
    t.text "location_template"
    t.jsonb "reminder_settings", default: []
    t.integer "scope", null: false
    t.text "title_template"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility"
    t.index ["user_id", "scope", "event_type"], name: "index_calendar_prefs_on_user_scope_type", unique: true
    t.index ["user_id"], name: "index_calendar_preferences_on_user_id"
  end

  create_table "console1984_commands", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "sensitive_access_id"
    t.bigint "session_id", null: false
    t.text "statements"
    t.datetime "updated_at", null: false
    t.index ["sensitive_access_id"], name: "index_console1984_commands_on_sensitive_access_id"
    t.index ["session_id", "created_at", "sensitive_access_id"], name: "on_session_and_sensitive_chronologically"
  end

  create_table "console1984_sensitive_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "justification"
    t.bigint "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_console1984_sensitive_accesses_on_session_id"
  end

  create_table "console1984_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_console1984_sessions_on_created_at"
    t.index ["user_id", "created_at"], name: "index_console1984_sessions_on_user_id_and_created_at"
  end

  create_table "console1984_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_console1984_users_on_username"
  end

  create_table "courses", force: :cascade do |t|
    t.integer "course_number"
    t.datetime "created_at", null: false
    t.integer "credit_hours"
    t.integer "crn"
    t.vector "embedding", limit: 1536
    t.date "end_date"
    t.string "grade_mode"
    t.string "schedule_type", null: false
    t.string "section_number", null: false
    t.date "start_date"
    t.string "subject"
    t.bigint "term_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["crn"], name: "index_courses_on_crn", unique: true
    t.index ["term_id"], name: "index_courses_on_term_id"
  end

  create_table "courses_faculties", id: false, force: :cascade do |t|
    t.bigint "course_id", null: false
    t.bigint "faculty_id", null: false
    t.index ["course_id", "faculty_id"], name: "index_courses_faculties_on_course_id_and_faculty_id"
    t.index ["faculty_id", "course_id"], name: "index_courses_faculties_on_faculty_id_and_course_id"
  end

  create_table "emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.boolean "g_cal", default: false, null: false
    t.boolean "primary", default: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["email"], name: "index_emails_on_email", unique: true
    t.index ["user_id", "primary"], name: "index_emails_on_user_id_and_primary", unique: true, where: "(\"primary\" = true)"
    t.index ["user_id"], name: "index_emails_on_user_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.datetime "created_at", null: false
    t.bigint "term_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["course_id"], name: "index_enrollments_on_course_id"
    t.index ["term_id"], name: "index_enrollments_on_term_id"
    t.index ["user_id", "course_id", "term_id"], name: "index_enrollments_on_user_class_term", unique: true
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
    t.index ["preferenceable_type", "preferenceable_id"], name: "index_event_prefs_on_preferenceable"
    t.index ["user_id", "preferenceable_type", "preferenceable_id"], name: "index_event_prefs_on_user_and_preferenceable", unique: true
    t.index ["user_id"], name: "index_event_preferences_on_user_id"
  end

  create_table "faculties", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.vector "embedding", limit: 1536
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "rmp_id"
    t.jsonb "rmp_raw_data", default: {}
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_faculties_on_email", unique: true
    t.index ["rmp_id"], name: "index_faculties_on_rmp_id", unique: true
    t.index ["rmp_raw_data"], name: "index_faculties_on_rmp_raw_data", using: :gin
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "google_calendar_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time"
    t.string "event_data_hash"
    t.bigint "google_calendar_id", null: false
    t.string "google_event_id", null: false
    t.datetime "last_synced_at"
    t.string "location"
    t.bigint "meeting_time_id"
    t.text "recurrence"
    t.datetime "start_time"
    t.string "summary"
    t.datetime "updated_at", null: false
    t.index ["google_calendar_id", "meeting_time_id"], name: "idx_on_google_calendar_id_meeting_time_id_6c9efabf50"
    t.index ["google_calendar_id"], name: "index_google_calendar_events_on_google_calendar_id"
    t.index ["google_event_id"], name: "index_google_calendar_events_on_google_event_id"
    t.index ["last_synced_at"], name: "index_google_calendar_events_on_last_synced_at"
    t.index ["meeting_time_id"], name: "index_google_calendar_events_on_meeting_time_id"
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

  create_table "lab_credit_hours_backup", primary_key: "course_id", id: :bigint, default: nil, force: :cascade do |t|
    t.integer "original_credit_hours"
  end

  create_table "lockbox_audits", force: :cascade do |t|
    t.string "context"
    t.datetime "created_at"
    t.jsonb "data"
    t.string "ip"
    t.bigint "subject_id"
    t.string "subject_type"
    t.bigint "viewer_id"
    t.string "viewer_type"
    t.index ["subject_type", "subject_id"], name: "index_lockbox_audits_on_subject"
    t.index ["viewer_type", "viewer_id"], name: "index_lockbox_audits_on_viewer"
  end

  create_table "mailkick_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "list"
    t.bigint "subscriber_id"
    t.string "subscriber_type"
    t.datetime "updated_at", null: false
    t.index ["subscriber_type", "subscriber_id", "list"], name: "index_mailkick_subscriptions_on_subscriber_and_list", unique: true
  end

  create_table "meeting_times", force: :cascade do |t|
    t.integer "begin_time", null: false
    t.bigint "course_id", null: false
    t.datetime "created_at", null: false
    t.integer "day_of_week"
    t.datetime "end_date", null: false
    t.integer "end_time", null: false
    t.integer "hours_week"
    t.integer "meeting_schedule_type"
    t.integer "meeting_type"
    t.bigint "room_id", null: false
    t.datetime "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_meeting_times_on_course_id"
    t.index ["day_of_week"], name: "index_meeting_times_on_day_of_week"
    t.index ["room_id"], name: "index_meeting_times_on_room_id"
  end

  create_table "oauth_credentials", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.jsonb "metadata", default: {}
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

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "searchable_id"
    t.string "searchable_type"
    t.datetime "updated_at", null: false
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
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
    t.vector "embedding", limit: 1536
    t.bigint "faculty_id", null: false
    t.string "grade"
    t.integer "helpful_rating"
    t.boolean "is_for_credit"
    t.boolean "is_for_online_class"
    t.datetime "rating_date"
    t.text "rating_tags"
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
    t.integer "number"
    t.datetime "updated_at", null: false
    t.index ["building_id"], name: "index_rooms_on_building_id"
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
    t.boolean "catalog_imported", default: false, null: false
    t.datetime "catalog_imported_at"
    t.datetime "created_at", null: false
    t.integer "season"
    t.integer "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["uid"], name: "index_terms_on_uid", unique: true
    t.index ["year", "season"], name: "index_terms_on_year_and_season", unique: true
  end

  create_table "user_extension_configs", force: :cascade do |t|
    t.boolean "advanced_editing", default: false, null: false
    t.datetime "created_at", null: false
    t.string "default_color_lab", default: "#f6bf26", null: false
    t.string "default_color_lecture", default: "#039be5", null: false
    t.boolean "military_time", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_user_extension_configs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "access_level", default: 0, null: false
    t.boolean "calendar_needs_sync", default: false, null: false
    t.string "calendar_token"
    t.datetime "created_at", null: false
    t.string "first_name"
    t.datetime "last_calendar_sync_at"
    t.string "last_name"
    t.datetime "updated_at", null: false
    t.index ["calendar_needs_sync"], name: "index_users_on_calendar_needs_sync"
    t.index ["calendar_token"], name: "index_users_on_calendar_token", unique: true
    t.index ["last_calendar_sync_at"], name: "index_users_on_last_calendar_sync_at"
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "calendar_preferences", "users"
  add_foreign_key "courses", "terms"
  add_foreign_key "emails", "users"
  add_foreign_key "enrollments", "courses"
  add_foreign_key "enrollments", "terms"
  add_foreign_key "enrollments", "users"
  add_foreign_key "event_preferences", "users"
  add_foreign_key "google_calendar_events", "google_calendars"
  add_foreign_key "google_calendar_events", "meeting_times"
  add_foreign_key "google_calendars", "oauth_credentials"
  add_foreign_key "meeting_times", "courses"
  add_foreign_key "meeting_times", "rooms"
  add_foreign_key "oauth_credentials", "users"
  add_foreign_key "rating_distributions", "faculties", validate: false
  add_foreign_key "related_professors", "faculties", column: "related_faculty_id", validate: false
  add_foreign_key "related_professors", "faculties", validate: false
  add_foreign_key "rmp_ratings", "faculties", validate: false
  add_foreign_key "rooms", "buildings"
  add_foreign_key "security_events", "oauth_credentials"
  add_foreign_key "security_events", "users"
  add_foreign_key "teacher_rating_tags", "faculties", validate: false
  add_foreign_key "user_extension_configs", "users"
end
