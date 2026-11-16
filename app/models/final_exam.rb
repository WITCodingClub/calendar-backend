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

  belongs_to :term
  belongs_to :course, optional: true
  # Nullify, never destroy: see Course::MeetingTime — destroying tracking rows
  # strands the real events in Google Calendar.
  has_many :calendar_events, dependent: :nullify

  validates :crn, presence: true
  validates :exam_date, :start_time, :end_time, presence: true
  validates :crn, uniqueness: { scope: :term_id, message: "can only have one final exam per CRN per term" }
  validate :end_time_after_start_time

  before_save :link_course, if: -> { course_id.nil? }

  serialize :combined_crns, coder: JSON

  delegate :title, to: :course, prefix: true, allow_nil: true

  scope :orphan,   -> { where(course_id: nil) }
  scope :linked,   -> { where.not(course_id: nil) }
  scope :upcoming, -> { where(exam_date: Time.zone.today..) }

  # A date counts as part of finals week when it holds at least this share of
  # the term's exams.
  FINALS_WEEK_MIN_SHARE = 0.1

  # The first day of the term's finals week, or nil when the term has no exams.
  # A course with no final stops its classes the day before.
  #
  # This is not the earliest exam date. A few sections hold their "final"
  # weeks early: in Fall 2026, 8 Global Research Studio sections had one on
  # Nov 19, and the classes of every course with no final stopped on Nov 18.
  def self.finals_week_start(term_id)
    finals_week_starts([ term_id ])[term_id]
  end

  # finals_week_start for each of the terms, from one query. A term with no
  # exams has no key.
  def self.finals_week_starts(term_ids)
    where(term_id: term_ids).group(:term_id, :exam_date).count
                            .group_by { |(term_id, _date), _count| term_id }
                            .transform_values do |rows|
      counts = rows.to_h { |(_term_id, date), count| [ date, count ] }
      total  = counts.values.sum
      busy_dates = counts.select { |_date, count| count >= total * FINALS_WEEK_MIN_SHARE }.keys
      (busy_dates.presence || counts.keys).min
    end
  end

  def linked?   = course.present?
  def orphan?   = course.blank?

  def formatted_start_time      = start_time && Hhmm.format(start_time)
  def formatted_end_time        = end_time && Hhmm.format(end_time)
  def formatted_start_time_ampm = start_time && Hhmm.format_12h(start_time)
  def formatted_end_time_ampm   = end_time && Hhmm.format_12h(end_time)

  def duration_hours
    return 0 unless start_time && end_time

    Hhmm.duration_hours(start_time, end_time)
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

  # Some stored rows hold the JSON text as a JSON string (double-encoded), so
  # the serializer gives back a String, not an Array.
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

    Hhmm.on(exam_date, start_time)
  end

  def end_datetime
    return nil unless exam_date && end_time

    Hhmm.on(exam_date, end_time)
  end

  # The location with building names in place of abbreviations. Pass the
  # exam's rooms from FinalsSchedules::ExamRooms.part_rooms_for to skip the
  # queries.
  def location_with_names(part_rooms = FinalsSchedules::ExamRooms.part_rooms_for([ self ])[self])
    FinalsSchedules::ExamRooms.named_location(location, part_rooms)
  end

  private

  # The finals parser looks up the course before it saves, so a course created
  # between the two leaves the exam unlinked. Look it up again on every save
  # with no course.
  def link_course
    self.course = Course.find_by(crn: crn, term_id: term_id)
  end

  def end_time_after_start_time
    return unless start_time && end_time

    errors.add(:end_time, "must be after start time") if end_time <= start_time
  end
end
