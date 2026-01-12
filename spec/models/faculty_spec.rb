# frozen_string_literal: true

# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  department               :string
#  directory_last_synced_at :datetime
#  directory_raw_data       :jsonb
#  display_name             :string
#  email                    :string           not null
#  embedding                :vector(1536)
#  employee_type            :string
#  first_name               :string           not null
#  last_name                :string           not null
#  middle_name              :string
#  office_location          :string
#  phone                    :string
#  photo_url                :string
#  rmp_raw_data             :jsonb
#  school                   :string
#  title                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  rmp_id                   :string
#
# Indexes
#
#  index_faculties_on_department                (department)
#  index_faculties_on_directory_last_synced_at  (directory_last_synced_at)
#  index_faculties_on_directory_raw_data        (directory_raw_data) USING gin
#  index_faculties_on_email                     (email) UNIQUE
#  index_faculties_on_employee_type             (employee_type)
#  index_faculties_on_rmp_id                    (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data              (rmp_raw_data) USING gin
#  index_faculties_on_school                    (school)
#
require "rails_helper"

RSpec.describe Faculty do
  describe "validations" do
    it "is valid with valid attributes" do
      faculty = build(:faculty)
      expect(faculty).to be_valid
    end

    it "enforces rmp_id uniqueness" do
      create(:faculty, rmp_id: "12345")
      duplicate = build(:faculty, rmp_id: "12345")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:rmp_id]).to include("has already been taken")
    end

    it "allows nil rmp_id" do
      faculty = build(:faculty, rmp_id: nil)
      expect(faculty).to be_valid
    end

    it "allows multiple faculty with nil rmp_id" do
      create(:faculty, rmp_id: nil)
      faculty = build(:faculty, rmp_id: nil)
      expect(faculty).to be_valid
    end
  end

  describe "associations" do
    it "has many rmp_ratings" do
      faculty = create(:faculty)
      rating = create(:rmp_rating, faculty: faculty)
      expect(faculty.rmp_ratings).to include(rating)
    end

    it "has many related_professors" do
      faculty = create(:faculty)
      related = create(:related_professor, faculty: faculty)
      expect(faculty.related_professors).to include(related)
    end

    it "has one rating_distribution" do
      faculty = create(:faculty)
      distribution = create(:rating_distribution, faculty: faculty)
      expect(faculty.rating_distribution).to eq(distribution)
    end

    it "has many teacher_rating_tags" do
      faculty = create(:faculty)
      tag = create(:teacher_rating_tag, faculty: faculty)
      expect(faculty.teacher_rating_tags).to include(tag)
    end

    it "destroys associated rmp_ratings when destroyed" do
      faculty = create(:faculty)
      create(:rmp_rating, faculty: faculty)
      expect { faculty.destroy }.to change(RmpRating, :count).by(-1)
    end
  end

  describe "scopes" do
    describe ".faculty_only" do
      it "returns only faculty members" do
        faculty = create(:faculty, employee_type: "faculty")
        staff = create(:faculty, employee_type: "staff")

        expect(described_class.faculty_only).to include(faculty)
        expect(described_class.faculty_only).not_to include(staff)
      end
    end

    describe ".staff_only" do
      it "returns only staff members" do
        faculty = create(:faculty, employee_type: "faculty")
        staff = create(:faculty, employee_type: "staff")

        expect(described_class.staff_only).to include(staff)
        expect(described_class.staff_only).not_to include(faculty)
      end
    end

    describe ".by_school" do
      it "filters by school" do
        engineering = create(:faculty, school: "Engineering")
        sciences = create(:faculty, school: "Sciences")

        expect(described_class.by_school("Engineering")).to include(engineering)
        expect(described_class.by_school("Engineering")).not_to include(sciences)
      end
    end

    describe ".by_department" do
      it "filters by department" do
        cs = create(:faculty, department: "Computer Science")
        math = create(:faculty, department: "Mathematics")

        expect(described_class.by_department("Computer Science")).to include(cs)
        expect(described_class.by_department("Computer Science")).not_to include(math)
      end
    end

    describe ".needs_directory_sync" do
      it "returns faculty without directory sync" do
        never_synced = create(:faculty, directory_last_synced_at: nil)
        recently_synced = create(:faculty, directory_last_synced_at: 1.day.ago)
        stale_sync = create(:faculty, directory_last_synced_at: 8.days.ago)

        expect(described_class.needs_directory_sync).to include(never_synced, stale_sync)
        expect(described_class.needs_directory_sync).not_to include(recently_synced)
      end
    end

    describe ".with_directory_data" do
      it "returns faculty with directory data" do
        with_data = create(:faculty, directory_last_synced_at: 1.day.ago)
        without_data = create(:faculty, directory_last_synced_at: nil)

        expect(described_class.with_directory_data).to include(with_data)
        expect(described_class.with_directory_data).not_to include(without_data)
      end
    end
  end

  describe "#full_name" do
    it "returns display_name when present" do
      faculty = build(:faculty, display_name: "Dr. John Smith", first_name: "John", last_name: "Smith")
      expect(faculty.full_name).to eq("Dr. John Smith")
    end

    it "combines first, middle, and last name when display_name is blank" do
      faculty = build(:faculty, display_name: nil, first_name: "John", middle_name: "Michael", last_name: "Smith")
      expect(faculty.full_name).to eq("John Michael Smith")
    end

    it "handles nil middle name" do
      faculty = build(:faculty, display_name: nil, first_name: "John", middle_name: nil, last_name: "Smith")
      expect(faculty.full_name).to eq("John Smith")
    end
  end

  describe "#initials" do
    it "returns first letter of first and last name" do
      faculty = build(:faculty, first_name: "John", last_name: "Smith")
      expect(faculty.initials).to eq("JS")
    end
  end

  describe "#u_name" do
    it "returns forward and reverse name formats" do
      faculty = build(:faculty, first_name: "John", last_name: "Smith")
      expect(faculty.u_name).to eq({
        fwd: "J. Smith",
        rev: "Smith, J."
      })
    end
  end

  describe "#formal_name" do
    it "includes title when present" do
      faculty = build(:faculty, title: "Dr.", first_name: "John", last_name: "Smith")
      expect(faculty.formal_name).to eq("Dr. John Smith")
    end

    it "works without title" do
      faculty = build(:faculty, title: nil, first_name: "John", last_name: "Smith")
      expect(faculty.formal_name).to eq("John Smith")
    end
  end

  describe "#has_directory_data?" do
    it "returns true when directory_last_synced_at is present" do
      faculty = build(:faculty, directory_last_synced_at: 1.day.ago)
      expect(faculty.has_directory_data?).to be true
    end

    it "returns true when directory_raw_data is present" do
      faculty = build(:faculty, directory_last_synced_at: nil, directory_raw_data: { "name" => "John" })
      expect(faculty.has_directory_data?).to be true
    end

    it "returns false when neither is present" do
      faculty = build(:faculty, directory_last_synced_at: nil, directory_raw_data: nil)
      expect(faculty.has_directory_data?).to be false
    end
  end

  describe "#needs_directory_data?" do
    it "returns true when has no directory data" do
      faculty = build(:faculty, directory_last_synced_at: nil, directory_raw_data: nil)
      expect(faculty.needs_directory_data?).to be true
    end

    it "returns false when has directory data" do
      faculty = build(:faculty, directory_last_synced_at: 1.day.ago)
      expect(faculty.needs_directory_data?).to be false
    end
  end

  describe "#teaches_courses?" do
    it "returns true when faculty has courses" do
      faculty = create(:faculty)
      course = create(:course)
      faculty.courses << course

      expect(faculty.teaches_courses?).to be true
    end

    it "returns false when faculty has no courses" do
      faculty = create(:faculty)
      expect(faculty.teaches_courses?).to be false
    end
  end

  describe "#directory_data_age" do
    it "returns nil when never synced" do
      faculty = build(:faculty, directory_last_synced_at: nil)
      expect(faculty.directory_data_age).to be_nil
    end

    it "returns age in seconds when synced" do
      faculty = build(:faculty, directory_last_synced_at: 1.hour.ago)
      expect(faculty.directory_data_age).to be_within(60).of(3600)
    end
  end

  describe "#rmp_stats" do
    it "returns nil when no rating_distribution" do
      faculty = create(:faculty)
      expect(faculty.rmp_stats).to be_nil
    end

    it "returns stats from rating_distribution" do
      faculty = create(:faculty)
      create(:rating_distribution,
             faculty: faculty,
             avg_rating: 4.5,
             avg_difficulty: 3.0,
             num_ratings: 100,
             would_take_again_percent: 85.0)

      stats = faculty.rmp_stats
      expect(stats[:avg_rating]).to eq(4.5)
      expect(stats[:avg_difficulty]).to eq(3.0)
      expect(stats[:num_ratings]).to eq(100)
      expect(stats[:would_take_again_percent]).to eq(85.0)
    end
  end

  describe "#calculate_rating_stats" do
    it "returns empty hash when no ratings" do
      faculty = create(:faculty)
      expect(faculty.calculate_rating_stats).to eq({})
    end

    it "calculates stats from rmp_ratings" do
      faculty = create(:faculty)
      create(:rmp_rating, faculty: faculty, clarity_rating: 4.0, difficulty_rating: 3.0, would_take_again: true)
      create(:rmp_rating, faculty: faculty, clarity_rating: 5.0, difficulty_rating: 2.0, would_take_again: true)
      create(:rmp_rating, faculty: faculty, clarity_rating: 3.0, difficulty_rating: 4.0, would_take_again: false)

      stats = faculty.calculate_rating_stats
      expect(stats[:avg_rating]).to eq(4.0)
      expect(stats[:avg_difficulty]).to eq(3.0)
      expect(stats[:num_ratings]).to eq(3)
      expect(stats[:would_take_again_percent]).to be_within(0.1).of(66.67)
    end
  end

  describe "#update_ratings!" do
    it "enqueues UpdateFacultyRatingsJob" do
      faculty = create(:faculty)
      expect {
        faculty.update_ratings!
      }.to have_enqueued_job(UpdateFacultyRatingsJob).with(faculty.id)
    end
  end

  describe "#rmp_numeric_id" do
    it "extracts numeric ID from base64-encoded GraphQL ID" do
      # "Teacher-2196214" encoded as base64
      encoded_id = Base64.strict_encode64("Teacher-2196214")
      faculty = build(:faculty, rmp_id: encoded_id)
      expect(faculty.rmp_numeric_id).to eq("2196214")
    end

    it "returns nil when rmp_id is blank" do
      faculty = build(:faculty, rmp_id: nil)
      expect(faculty.rmp_numeric_id).to be_nil
    end

    it "returns nil when rmp_id is empty string" do
      faculty = build(:faculty, rmp_id: "")
      expect(faculty.rmp_numeric_id).to be_nil
    end

    it "returns original ID when already numeric" do
      faculty = build(:faculty, rmp_id: "12345")
      expect(faculty.rmp_numeric_id).to eq("12345")
    end

    it "returns original ID when base64 decodes to unexpected format" do
      # Valid base64 that doesn't decode to "Teacher-XXXXX" format
      encoded_id = Base64.strict_encode64("InvalidFormat")
      faculty = build(:faculty, rmp_id: encoded_id)
      expect(faculty.rmp_numeric_id).to eq(encoded_id)
    end

    it "returns original ID when base64 decodes to non-numeric suffix" do
      encoded_id = Base64.strict_encode64("Teacher-abc123")
      faculty = build(:faculty, rmp_id: encoded_id)
      expect(faculty.rmp_numeric_id).to eq(encoded_id)
    end
  end

  describe "public_id" do
    it "generates a public_id with fac prefix" do
      faculty = create(:faculty)
      expect(faculty.public_id).to start_with("fac_")
    end
  end
end
