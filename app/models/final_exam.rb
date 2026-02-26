# frozen_string_literal: true

# == Schema Information
#
# Table name: final_exams
# Database name: primary
#
#  id            :bigint           not null, primary key
#  combined_crns :text
#  crn           :integer
#  end_time      :integer          not null
#  exam_date     :date             not null
#  location      :string
#  notes         :text
#  start_time    :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  course_id     :bigint
#  term_id       :bigint           not null
#
# Indexes
#
#  index_final_exams_on_course_id        (course_id)
#  index_final_exams_on_crn_and_term_id  (crn,term_id) UNIQUE
#  index_final_exams_on_term_id          (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
class FinalExam < ApplicationRecord
  belongs_to :course, optional: true
  belongs_to :term
  has_many :google_calendar_events, dependent: :destroy
  include EncodedIds::HashidIdentifiable

  validates :crn, presence: true
  validates :exam_date, :start_time, :end_time, presence: true
  validates :crn, uniqueness: { scope: :term_id, message: "can only have one final exam per CRN per term" }
  validate :end_time_after_start_time

  # Scopes for finding orphan vs linked exams
  scope :orphan, -> { where(course_id: nil) }
  scope :linked, -> { where.not(course_id: nil) }
  scope :for_crn, ->(crn) { where(crn: crn) }

  # Link orphan FinalExams to courses for a specific term
  # Call this after courses are imported/scraped
  def self.link_orphan_exams_to_courses(term:)
    linked_count = 0
    orphan.where(term: term).find_each do |final_exam|
      course = Course.find_by(crn: final_exam.crn, term: term)
      if course
        final_exam.update!(course: course)
        linked_count += 1
      end
    end
    linked_count
  end

  # Link this specific exam to its course
  def link_to_course!
    return if course.present? # Already linked

    found_course = Course.find_by(crn: crn, term: term)
    update!(course: found_course) if found_course
    found_course
  end

  # Check if this exam is linked to a course
  def linked?
    course.present?
  end

  # Check if this exam is orphaned (no course link)
  def orphan?
    course.blank?
  end

  # Serialize combined_crns as JSON array
  serialize :combined_crns, coder: JSON

  # Delegate course attributes for easy template access (only when course is present)
  delegate :title, :subject, :course_number, :section_number, :schedule_type, to: :course, prefix: true, allow_nil: true

  # Format time as HH:MM (e.g., 800 -> "08:00", 1530 -> "15:30")
  def formatted_start_time
    format_time(start_time)
  end

  def formatted_end_time
    format_time(end_time)
  end

  # Format with AM/PM (e.g., "8:00 AM")
  def formatted_start_time_ampm
    format_time_ampm(start_time)
  end

  def formatted_end_time_ampm
    format_time_ampm(end_time)
  end

  # Duration in hours
  def duration_hours
    return 0 unless start_time && end_time

    start_h = start_time / 100
    start_m = start_time % 100
    end_h = end_time / 100
    end_m = end_time % 100

    (((end_h * 60) + end_m) - ((start_h * 60) + start_m)) / 60.0
  end

  # Time of day category (morning, afternoon, evening)
  def time_of_day
    return nil unless start_time

    hour = start_time / 100
    case hour
    when 0..11 then "morning"
    when 12..16 then "afternoon"
    else "evening"
    end
  end

  # Get course code for display (e.g., "COMP-1000-01")
  def course_code
    return "CRN #{crn}" unless course

    "#{course.subject}-#{course.course_number}-#{course.section_number}"
  end

  # Get primary instructor name
  def primary_instructor
    return "TBA" unless course

    course.faculties.first&.full_name || "TBA"
  end

  # Get all instructor names
  def all_instructors
    return "TBA" unless course

    course.faculties.map(&:full_name).join(", ").presence || "TBA"
  end

  # Get all combined CRNs as formatted string
  def combined_crns_display
    (combined_crns || [crn]).join(", ")
  end

  # Build datetime for start of exam
  def start_datetime
    return nil unless exam_date && start_time

    Time.zone.local(
      exam_date.year,
      exam_date.month,
      exam_date.day,
      start_time / 100,
      start_time % 100
    )
  end

  # Build datetime for end of exam
  def end_datetime
    return nil unless exam_date && end_time

    Time.zone.local(
      exam_date.year,
      exam_date.month,
      exam_date.day,
      end_time / 100,
      end_time % 100
    )
  end

  # Try to find matching Room records from the location string
  # Returns array of Room objects (may be empty if no matches found)
  def matched_rooms
    return [] if location.blank?

    rooms = []

    # Location format: "BLDG 123" or "BLDG 123 / BLDG 456"
    location.split(" / ").each do |loc|
      next unless loc =~ /([A-Z]+)\s+(\d+[A-Z]?)/i

      abbrev = $1
      room_num = $2

      building = Building.find_by(abbreviation: abbrev)
      next unless building

      # Try to find room by number (strip leading zeros for comparison)
      room = building.rooms.find_by(number: room_num.to_i)
      rooms << room if room
    end

    rooms
  end

  # Check if we found matching rooms in the database
  def rooms_matched?
    matched_rooms.any?
  end

  # Get formatted location with building names (if matched)
  def location_with_names
    return location if location.blank?

    rooms = matched_rooms
    return location if rooms.empty?

    rooms.map { |r| "#{r.building.name} #{r.formatted_number}" }.join(" / ")
  end

  private

  def format_time(time_int)
    return nil unless time_int

    hours = time_int / 100
    minutes = time_int % 100
    format("%02d:%02d", hours, minutes)
  end

  def format_time_ampm(time_int)
    return nil unless time_int

    hours = time_int / 100
    minutes = time_int % 100
    meridian = hours >= 12 ? "PM" : "AM"
    hours %= 12
    hours = 12 if hours == 0
    format("%d:%02d %s", hours, minutes, meridian)
  end

  def end_time_after_start_time
    return unless start_time && end_time

    errors.add(:end_time, "must be after start time") if end_time <= start_time
  end

end
