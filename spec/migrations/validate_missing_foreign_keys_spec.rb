# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261009200000_add_missing_foreign_keys")
require Rails.root.join("db/migrate/20261009200100_validate_missing_foreign_keys")

# Production may hold rows that point at a deleted parent. These examples remove
# the new foreign keys, insert orphan rows by hand, and run both migrations as
# a deploy does. Parent rows that stay valid come from factories, like the other
# migration specs.
RSpec.describe ValidateMissingForeignKeys do
  subject(:migration) { build_migration }

  let(:add_keys)   { build_migration(AddMissingForeignKeys) }
  let(:connection) { ActiveRecord::Base.connection }
  let(:missing_id) { 2_000_000_000 }

  let(:keys) do
    [
      %w[calendar_events final_exams final_exam_id],
      %w[calendar_events university_calendar_events university_calendar_event_id],
      %w[courses_faculties courses course_id],
      %w[courses_faculties faculties faculty_id]
    ]
  end

  before do
    [ migration, add_keys ].each { |m| m.verbose = false }
    add_keys.migrate(:down)
  end

  def validated?(table, column)
    connection.select_value(<<~SQL.squish) == true
      SELECT convalidated FROM pg_constraint
      WHERE contype = 'f' AND conrelid = #{connection.quote(table)}::regclass
        AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
                            WHERE attrelid = #{connection.quote(table)}::regclass
                              AND attname = #{connection.quote(column)})]
    SQL
  end

  def all_keys_validated?
    keys.all? { |table, _, column| validated?(table, column) }
  end

  context "with orphan rows" do
    let(:calendar) { create(:course_calendar) }

    def insert_event(column, id)
      connection.select_value(<<~SQL.squish)
        INSERT INTO calendar_events (calendar_id, external_event_id, #{column}, created_at, updated_at)
        VALUES (#{calendar.id}, #{connection.quote(SecureRandom.hex(8))}, #{id}, NOW(), NOW())
        RETURNING id
      SQL
    end

    def insert_course_faculty(course_id, faculty_id)
      connection.select_value(<<~SQL.squish)
        INSERT INTO courses_faculties (course_id, faculty_id) VALUES (#{course_id}, #{faculty_id}) RETURNING id
      SQL
    end

    def event_row(id)
      connection.select_one("SELECT final_exam_id, university_calendar_event_id FROM calendar_events WHERE id = #{id}")
    end

    # The test transaction still holds the locks from add_foreign_key, and
    # strong_migrations stops a validation while those locks are held. A deploy
    # commits each migration first. The "on a deploy" group below runs the
    # same steps with every check on.
    def deploy
      add_keys.migrate(:up)
      StrongMigrations::Checker.safety_assured { migration.migrate(:up) }
    end

    it "nullifies a calendar event's final exam id when the exam is gone and keeps the row" do
      orphan = insert_event(:final_exam_id, missing_id)
      exam = create(:final_exam)
      linked = insert_event(:final_exam_id, exam.id)

      deploy

      expect(event_row(orphan)).to eq("final_exam_id" => nil, "university_calendar_event_id" => nil)
      expect(event_row(linked)["final_exam_id"]).to eq(exam.id)
    end

    it "nullifies a calendar event's university event id when the event is gone and keeps the row" do
      orphan = insert_event(:university_calendar_event_id, missing_id)
      source = create(:university_calendar_event)
      linked = insert_event(:university_calendar_event_id, source.id)

      deploy

      expect(event_row(orphan)["university_calendar_event_id"]).to be_nil
      expect(event_row(linked)["university_calendar_event_id"]).to eq(source.id)
    end

    it "leaves a nullified event for the orphan cleanup job to find" do
      orphan = insert_event(:final_exam_id, missing_id)

      deploy

      expect(CalendarEvent.orphaned.ids).to include(orphan)
    end

    it "deletes course-faculty rows with a missing course or faculty and keeps valid rows" do
      course = create(:course)
      faculty = create(:faculty)
      valid = insert_course_faculty(course.id, faculty.id)
      insert_course_faculty(missing_id, faculty.id)
      insert_course_faculty(course.id, missing_id)

      deploy

      expect(connection.select_values("SELECT id FROM courses_faculties")).to eq([ valid ])
    end

    it "validates all four foreign keys" do
      insert_event(:final_exam_id, missing_id)
      insert_event(:university_calendar_event_id, missing_id)
      insert_course_faculty(missing_id, missing_id)

      deploy

      expect(all_keys_validated?).to be(true)
    end

    it "nullifies calendar events when a final exam or university event is deleted with SQL" do
      exam = create(:final_exam)
      source = create(:university_calendar_event)
      exam_event = insert_event(:final_exam_id, exam.id)
      source_event = insert_event(:university_calendar_event_id, source.id)
      deploy

      FinalExam.where(id: exam.id).delete_all
      UniversityCalendarEvent.where(id: source.id).delete_all

      expect(event_row(exam_event)["final_exam_id"]).to be_nil
      expect(event_row(source_event)["university_calendar_event_id"]).to be_nil
    end

    it "rejects a new course-faculty row whose course does not exist" do
      deploy

      expect { insert_course_faculty(missing_id, create(:faculty).id) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  # Runs outside the test transaction, so each step commits as it does on a
  # deploy and strong_migrations checks every step. No rows are written.
  context "on a deploy" do
    self.use_transactional_tests = false

    after do
      add_keys.migrate(:up) unless connection.foreign_key_exists?(:courses_faculties, :faculties)
      migration.migrate(:up) unless all_keys_validated?
    end

    it "passes the strong_migrations checks and leaves valid foreign keys" do
      expect do
        add_keys.migrate(:up)
        migration.migrate(:up)
      end.not_to raise_error

      expect(all_keys_validated?).to be(true)
    end

    it "runs outside a transaction, so the cleanup does not hold row locks during the validation" do
      expect(described_class.disable_ddl_transaction).to be(true)
    end
  end
end
