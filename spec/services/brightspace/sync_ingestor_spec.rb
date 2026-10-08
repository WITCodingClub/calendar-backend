# frozen_string_literal: true

require "rails_helper"

RSpec.describe Brightspace::SyncIngestor do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let!(:connection) { create(:brightspace_connection, user: user, host: "brightspace.example.edu", learner_id: "98765") }
  let(:raw) { JSON.parse(file_fixture("brightspace/sync_snapshot.json").read) }

  def ingest(params = raw, as: user) = described_class.new(user: as, params: params).call
  def klass = raw["classes"][0]
  def offering = connection.course_offerings.find_by!(source_id: "12414")

  def next_snapshot(minutes: 10)
    raw["snapshot_id"] = SecureRandom.uuid
    raw["collected_at"] = (Time.iso8601(raw["collected_at"]) + minutes.minutes).iso8601
  end

  it "stores every section of the fixture" do
    result = ingest

    expect(result.body["status"]).to eq("complete")
    expect(result.body["changed_classes"]).to eq([ { "id" => offering.public_id, "version" => offering.version } ])
    expect(offering.assignments.pluck(:kind, :source_id)).to contain_exactly(%w[assignment 56789], %w[quiz 4410])
    expect(offering.announcements.count).to eq(1)
    expect(offering.grade_categories.pluck(:name)).to contain_exactly("Labs", "Quizzes")
    expect(offering.reported_total).to include("letter" => "B", "percent" => 83.0)
    expect(offering.syllabus.extracted).to eq(klass["syllabus"]["extracted"])
  end

  it "keeps a zero apart from an ungraded item and links items to work and categories" do
    ingest

    zero     = offering.grade_items.find_by!(source_id: "7003")
    ungraded = offering.grade_items.find_by!(source_id: "7002")

    expect(zero).to have_attributes(points_earned: 0, grading_status: "graded")
    expect(ungraded).to have_attributes(points_earned: nil, grading_status: "ungraded")
    expect(ungraded.assignment).to eq(offering.assignments.find_by!(source_id: "56789"))
    expect(ungraded.grade_category.name).to eq("Labs")
  end

  it "records the sync time and the section state" do
    freeze_time do
      ingest

      expect(connection.reload.last_synced_at).to eq(Time.current)
      expect(offering.section_state("assignments")).to include("collected_at" => "2026-10-06T17:00:00Z", "complete" => true)
    end
  end

  describe "repeated snapshots" do
    it "answers the same snapshot again without changes" do
      first = ingest
      version = offering.version

      second = ingest

      expect(second.replayed).to be(true)
      expect(second.body).to eq(first.body)
      expect(offering.version).to eq(version)
      expect(connection.syncs.count).to eq(1)
    end

    it "treats the same data in another key order as the same snapshot" do
      ingest

      expect(ingest(raw.to_a.reverse.to_h).replayed).to be(true)
    end

    it "rejects a snapshot id that comes back with other data" do
      ingest
      klass["title"] = "Something else"

      expect { ingest }.to raise_error(described_class::Conflict) { |error| expect(error.code).to eq("SNAPSHOT_CONFLICT") }
    end

    it "keeps the version for a new snapshot with the same data" do
      ingest
      version = offering.version
      next_snapshot

      result = ingest

      expect(result.body["changed_classes"]).to eq([])
      expect(offering.version).to eq(version)
    end

    it "raises the version when imported data changes" do
      ingest
      version = offering.version
      next_snapshot
      klass["assignments"][0]["due_at"] = "2026-10-10T03:59:00Z"

      result = ingest

      expect(offering.version).not_to eq(version)
      expect(result.body["changed_classes"]).to eq([ { "id" => offering.public_id, "version" => offering.version } ])
    end

    it "does not let an older snapshot overwrite newer data" do
      ingest
      raw["snapshot_id"] = SecureRandom.uuid
      raw["collected_at"] = "2026-10-06T16:00:00Z"
      klass["assignments"][0]["title"] = "Old title"

      ingest

      expect(offering.assignments.find_by!(source_id: "56789").title).to eq("Lab 4: Linked lists")
    end
  end

  describe "removals" do
    before { ingest }

    it "marks unlisted rows as removed in a complete section" do
      next_snapshot
      klass["assignments"].pop

      ingest

      quiz = offering.assignments.find_by!(kind: "quiz")
      expect(quiz.removed_at).to be_present
      expect(offering.assignments.not_removed.count).to eq(1)
    end

    it "keeps unlisted rows in a section that is not complete" do
      next_snapshot
      klass["complete_sections"] = [ "announcements", "grades" ]
      klass["assignments"].pop

      ingest

      expect(offering.assignments.not_removed.count).to eq(2)
    end

    it "leaves an omitted section alone" do
      next_snapshot
      klass.delete("assignments")
      klass["complete_sections"] = []

      ingest

      expect(offering.assignments.not_removed.count).to eq(2)
    end

    it "keeps the data of a section that failed and records the error" do
      next_snapshot
      klass["assignments"] = []
      klass["section_errors"] = { "assignments" => "Request timed out" }

      ingest

      expect(offering.assignments.not_removed.count).to eq(2)
      expect(offering.section_state("assignments")).to include("error" => "Request timed out",
                                                               "collected_at" => "2026-10-06T17:00:00Z")
    end

    it "brings a removed row back when a later sync lists it" do
      next_snapshot
      quiz = klass["assignments"].pop
      ingest
      next_snapshot
      klass["assignments"] << quiz

      ingest

      expect(offering.assignments.not_removed.count).to eq(2)
    end

    it "never touches the rows of another class" do
      other = create(:brightspace_course_offering, connection: connection)
      kept  = create(:brightspace_assignment, course_offering: other)
      next_snapshot
      klass["assignments"] = []

      ingest

      expect(kept.reload.removed_at).to be_nil
    end

    it "marks the syllabus removed when a complete section sends null" do
      next_snapshot
      klass["syllabus"] = nil
      klass["complete_sections"] << "syllabus"

      ingest

      expect(offering.syllabus.removed_at).to be_present
    end
  end

  describe "course mapping" do
    let(:course) { create(:course) }

    it "links a course from the user's enrollments" do
      create(:enrollment, user: user, course: course)
      klass["course_id"] = course.public_id

      ingest

      expect(offering).to have_attributes(course: course, term: course.term)
    end

    it "ignores a course the user is not enrolled in, with a warning" do
      klass["course_id"] = course.public_id

      result = ingest

      expect(offering.course).to be_nil
      expect(result.body["warnings"]).to contain_exactly(hash_including("class_source_id" => "12414"))
    end

    it "takes a term without a course" do
      term = create(:term)
      klass["term_id"] = term.public_id

      ingest

      expect(offering.term).to eq(term)
    end
  end

  describe "the linked account" do
    it "needs a linked account" do
      connection.disconnect!

      expect { ingest }.to raise_error(described_class::Conflict) { |error| expect(error.code).to eq("NOT_CONNECTED") }
    end

    it "rejects a snapshot from another account" do
      raw["learner_id"] = "11111"

      expect { ingest }.to raise_error(described_class::Conflict) { |error| expect(error.code).to eq("CONNECTION_MISMATCH") }
    end

    it "records that the extension must sign in again" do
      raw["reconnect_required"] = true

      ingest

      expect(connection.reload.reconnect_required_at).to be_present
    end

    it "keeps each user's data apart" do
      other_user = create(:user)
      other = create(:brightspace_connection, user: other_user, host: "brightspace.example.edu", learner_id: "98765")

      ingest
      ingest(as: other_user)

      expect(connection.course_offerings.count).to eq(1)
      expect(other.course_offerings.count).to eq(1)
      expect(other.course_offerings.first).not_to eq(offering)
    end
  end

  it "stores nothing when a row is invalid" do
    allow_any_instance_of(Brightspace::Announcement).to receive(:valid?).and_return(false) # rubocop:disable RSpec/AnyInstance

    expect { ingest }.to raise_error(ActiveRecord::RecordInvalid)
    expect(connection.course_offerings.count).to eq(0)
    expect(connection.syncs.count).to eq(0)
  end
end
