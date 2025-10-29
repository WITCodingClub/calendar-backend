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

ActiveRecord::Schema[8.1].define(version: 2025_10_29_210804) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "courses", force: :cascade do |t|
    t.integer "course_number"
    t.datetime "created_at", null: false
    t.integer "credit_hours"
    t.integer "crn"
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

  create_table "faculties", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_faculties_on_email", unique: true
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

  create_table "magic_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_magic_links_on_token", unique: true
    t.index ["user_id"], name: "index_magic_links_on_user_id"
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
    t.datetime "end_date", null: false
    t.integer "end_time", null: false
    t.boolean "friday"
    t.integer "hours_week"
    t.integer "meeting_schedule_type"
    t.integer "meeting_type"
    t.boolean "monday"
    t.bigint "room_id", null: false
    t.boolean "saturday"
    t.datetime "start_date", null: false
    t.boolean "sunday"
    t.boolean "thursday"
    t.boolean "tuesday"
    t.datetime "updated_at", null: false
    t.boolean "wednesday"
    t.index ["course_id"], name: "index_meeting_times_on_course_id"
    t.index ["room_id"], name: "index_meeting_times_on_room_id"
  end

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "searchable_id"
    t.string "searchable_type"
    t.datetime "updated_at", null: false
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
  end

  create_table "rooms", force: :cascade do |t|
    t.bigint "building_id", null: false
    t.datetime "created_at", null: false
    t.integer "number"
    t.datetime "updated_at", null: false
    t.index ["building_id"], name: "index_rooms_on_building_id"
  end

  create_table "terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "season"
    t.integer "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["uid"], name: "index_terms_on_uid", unique: true
    t.index ["year", "season"], name: "index_terms_on_year_and_season", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "access_level", default: 0, null: false
    t.string "calendar_token"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "updated_at", null: false
    t.index ["calendar_token"], name: "index_users_on_calendar_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
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

  add_foreign_key "courses", "terms"
  add_foreign_key "enrollments", "courses"
  add_foreign_key "enrollments", "terms"
  add_foreign_key "enrollments", "users"
  add_foreign_key "magic_links", "users"
  add_foreign_key "meeting_times", "courses"
  add_foreign_key "meeting_times", "rooms"
  add_foreign_key "rooms", "buildings"
end
