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

ActiveRecord::Schema[8.0].define(version: 2025_10_26_200335) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "academic_classes", force: :cascade do |t|
    t.bigint "term_id", null: false
    t.integer "crn"
    t.string "section_number", null: false
    t.string "subject"
    t.integer "course_number"
    t.string "title"
    t.integer "credit_hours"
    t.string "grade_mode"
    t.integer "schedule_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["term_id"], name: "index_academic_classes_on_term_id"
  end

  create_table "academic_classes_faculties", id: false, force: :cascade do |t|
    t.bigint "academic_class_id", null: false
    t.bigint "faculty_id", null: false
    t.index ["academic_class_id", "faculty_id"], name: "idx_on_academic_class_id_faculty_id_109759805b"
    t.index ["faculty_id", "academic_class_id"], name: "idx_on_faculty_id_academic_class_id_91a0403041"
  end

  create_table "buildings", force: :cascade do |t|
    t.string "abbreviation", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "faculties", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "meeting_times", force: :cascade do |t|
    t.bigint "academic_class_id", null: false
    t.bigint "room_id", null: false
    t.integer "begin_time", null: false
    t.integer "end_time", null: false
    t.datetime "start_date", null: false
    t.datetime "end_date", null: false
    t.integer "hoursWeek"
    t.integer "meetingScheduleType"
    t.integer "meetingType"
    t.boolean "monday"
    t.boolean "tuesday"
    t.boolean "wednesday"
    t.boolean "thursday"
    t.boolean "friday"
    t.boolean "saturday"
    t.boolean "sunday"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["academic_class_id"], name: "index_meeting_times_on_academic_class_id"
    t.index ["room_id"], name: "index_meeting_times_on_room_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.integer "number"
    t.bigint "building_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["building_id"], name: "index_rooms_on_building_id"
  end

  create_table "terms", force: :cascade do |t|
    t.string "uid", null: false
    t.integer "year", null: false
    t.integer "semester", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["year", "semester"], name: "index_terms_on_year_and_semester", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "access_level", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "academic_classes", "terms"
  add_foreign_key "meeting_times", "academic_classes"
  add_foreign_key "meeting_times", "rooms"
  add_foreign_key "rooms", "buildings"
end
