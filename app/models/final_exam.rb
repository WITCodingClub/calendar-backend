# frozen_string_literal: true

class FinalExam < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fex

  belongs_to :term
  belongs_to :course, optional: true
  has_many :google_calendar_events, dependent: :destroy

  validates :crn, presence: true
  validates :exam_date, :start_time, :end_time, presence: true
  validates :crn, uniqueness: { scope: :term_id, message: "can only have one final exam per CRN per term" }
  validate :end_time_after_start_time

  serialize :combined_crns, coder: JSON

  delegate :title, :subject, :course_number, :section_number, :schedule_type,
           to: :course, prefix: true, allow_nil: true

  scope :orphan,   -> { where(course_id: nil) }
  scope :linked,   -> { where.not(course_id: nil) }
  scope :for_crn,  ->(crn) { where(crn: crn) }
  scope :upcoming, -> { where(exam_date: Time.zone.today..) }

  def self.link_orphan_exams_to_courses(term:)
    linked_count = 0
    orphan_exams = orphan.where(term: term).to_a
    courses_by_crn = Course.where(crn: orphan_exams.map(&:crn).uniq, term: term).index_by(&:crn)

    orphan_exams.each do |exam|
      if (course = courses_by_crn[exam.crn])
        exam.update!(course: course)
        linked_count += 1
      end
    end
    linked_count
  end

  def link_to_course!
    return if course.present?

    found_course = Course.find_by(crn: crn, term: term)
    update!(course: found_course) if found_course
    found_course
  end

  def linked?   = course.present?
  def orphan?   = course.blank?

  def formatted_start_time      = format_time(start_time)
  def formatted_end_time        = format_time(end_time)
  def formatted_start_time_ampm = format_time_ampm(start_time)
  def formatted_end_time_ampm   = format_time_ampm(end_time)

  def duration_hours
    return 0 unless start_time && end_time

    (((end_time / 100 * 60) + (end_time % 100)) - ((start_time / 100 * 60) + (start_time % 100))) / 60.0
  end

  def time_of_day
    return nil unless start_time

    case start_time / 100
    when 0..11  then "morning"
    when 12..16 then "afternoon"
    else             "evening"
    end
  end

  def course_code
    return "CRN #{crn}" unless course

    "#{course.subject}-#{course.course_number}-#{course.section_number}"
  end

  def primary_instructor
    course&.faculties&.first&.full_name || "TBA"
  end

  def all_instructors
    course&.faculties&.map(&:full_name)&.join(", ").presence || "TBA"
  end

  def combined_crns_display
    (combined_crns || [ crn ]).join(", ")
  end

  def start_datetime
    return nil unless exam_date && start_time

    Time.zone.local(exam_date.year, exam_date.month, exam_date.day, start_time / 100, start_time % 100)
  end

  def end_datetime
    return nil unless exam_date && end_time

    Time.zone.local(exam_date.year, exam_date.month, exam_date.day, end_time / 100, end_time % 100)
  end

  def matched_rooms
    return [] if location.blank?

    parts = location.split(" / ").filter_map do |loc|
      next unless loc =~ /([A-Z]+)\s+(\d+[A-Z]?)/i

      { abbrev: $1, room_num: $2.to_i.to_s }
    end
    return [] if parts.empty?

    abbrevs = parts.pluck(:abbrev).uniq
    buildings_by_abbrev = Building.where(abbreviation: abbrevs).index_by(&:abbreviation)
    building_ids = buildings_by_abbrev.values.map(&:id)
    room_numbers = parts.pluck(:room_num).uniq
    rooms_by_key = Room.where(building_id: building_ids, number: room_numbers)
                       .includes(:building)
                       .index_by { |r| [ r.building_id, r.number.to_s ] }

    parts.filter_map do |p|
      building = buildings_by_abbrev[p[:abbrev]]
      next unless building

      rooms_by_key[[ building.id, p[:room_num] ]]
    end
  end

  def rooms_matched? = matched_rooms.any?

  def location_with_names
    return location if location.blank?

    rooms = matched_rooms
    return location if rooms.empty?

    rooms.map { |r| "#{r.building.name} #{r.formatted_number}" }.join(" / ")
  end

  private

  def format_time(time_int)
    return nil unless time_int

    format("%02d:%02d", time_int / 100, time_int % 100)
  end

  def format_time_ampm(time_int)
    return nil unless time_int

    hours = time_int / 100
    minutes = time_int % 100
    meridian = hours >= 12 ? "PM" : "AM"
    hours = hours % 12
    hours = 12 if hours == 0
    format("%d:%02d %s", hours, minutes, meridian)
  end

  def end_time_after_start_time
    return unless start_time && end_time

    errors.add(:end_time, "must be after start time") if end_time <= start_time
  end
end
