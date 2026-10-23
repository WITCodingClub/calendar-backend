# frozen_string_literal: true

# == Schema Information
#
# Table name: final_exams
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
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fex

  # "WENT 210" or "WENT 2A": a building abbreviation, then a room number that
  # can end in letters.
  ROOM_PATTERN = /([A-Z]+)\s+(\d+[A-Z]*)/i

  belongs_to :term
  belongs_to :course, optional: true
  # Nullify, never destroy: see Course::MeetingTime — destroying tracking rows
  # strands the real events in Google Calendar.
  has_many :calendar_events, dependent: :nullify

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

  # Rows imported from the old backend hold the JSON text as a JSON string
  # (double-encoded), so the serializer gives back a String, not an Array.
  def combined_crns
    value = super
    return value unless value.is_a?(String)

    parsed = JSON.parse(value)
    parsed.is_a?(Array) ? parsed : [ parsed ]
  rescue JSON::ParserError
    value.split(/[\s,-]+/).compact_blank
  end

  def combined_crns_display
    (combined_crns.presence || [ crn ]).join(", ")
  end

  def start_datetime
    return nil unless exam_date && start_time

    Time.zone.local(exam_date.year, exam_date.month, exam_date.day, start_time / 100, start_time % 100)
  end

  def end_datetime
    return nil unless exam_date && end_time

    Time.zone.local(exam_date.year, exam_date.month, exam_date.day, end_time / 100, end_time % 100)
  end

  # The rooms that each exam's location names, with the same queries for one
  # exam or many.
  # @return [Hash{FinalExam => Array<Room>}]
  def self.matched_rooms_for(exams)
    part_rooms_for(exams).transform_values(&:compact)
  end

  # The room of each " / " part of each exam's location, or nil for a part
  # with no known room.
  # @return [Hash{FinalExam => Array<Room, nil>}]
  def self.part_rooms_for(exams)
    parts_by_exam = exams.index_with(&:location_parts)
    parts = parts_by_exam.values.flatten.compact
    return parts_by_exam if parts.empty?

    buildings_by_abbrev = Building.where(abbreviation: parts.pluck(:abbrev).uniq).index_by(&:abbreviation)
    rooms_by_key = Room.where(building_id: buildings_by_abbrev.values.map(&:id))
                       .includes(:building)
                       .index_by { |r| [ r.building_id, Room.number_key(r.number) ] }

    parts_by_exam.transform_values do |exam_parts|
      exam_parts.map do |p|
        building = p && buildings_by_abbrev[p[:abbrev]]
        next unless building

        rooms_by_key[[ building.id, p[:room_key] ]]
      end
    end
  end

  # Each " / " part of the location as a building abbreviation and a
  # Room.number_key, or nil for a part that is not "ABBR 123".
  def location_parts
    return [] if location.blank?

    location.split(" / ").map do |loc|
      next unless loc =~ ROOM_PATTERN

      { abbrev: $1, room_key: Room.number_key($2) }
    end
  end

  def matched_rooms = self.class.matched_rooms_for([ self ])[self]

  def rooms_matched? = matched_rooms.any?

  # Names each part of the location that matches a room, and keeps the text of
  # the other parts. Pass the rooms from part_rooms_for to skip the queries.
  def location_with_names(part_rooms = self.class.part_rooms_for([ self ])[self])
    return location if location.blank?

    location.split(" / ").each_with_index.map do |part, i|
      room = part_rooms[i]
      room ? "#{room.building.name} #{room.formatted_number}" : part
    end.join(" / ")
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
