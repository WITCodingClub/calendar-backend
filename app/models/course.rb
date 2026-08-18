# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  credit_hours      :integer
#  crn               :integer          not null
#  end_date          :date             not null
#  grade_mode        :string
#  is_section_linked :boolean          default(FALSE), not null
#  link_identifier   :string
#  schedule_type     :string           not null
#  seats_available   :integer
#  seats_capacity    :integer
#  section_number    :string           not null
#  start_date        :date             not null
#  status            :string           default("active"), not null
#  subject           :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  term_id           :bigint           not null
#
# Indexes
#
#  index_courses_on_course_and_link_identifier  (term_id,subject,course_number,link_identifier)
#  index_courses_on_crn_and_term_id             (crn,term_id) UNIQUE
#  index_courses_on_status                      (status)
#  index_courses_on_term_id                     (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class Course < ApplicationRecord
  include CourseChangeTrackable
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :crs

  def to_param
    public_id
  end

  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, class_name: "Course::MeetingTime", dependent: :destroy
  has_many :meeting_time_rooms, class_name: "Course::MeetingTimeRoom", through: :meeting_times
  has_many :rooms, through: :meeting_time_rooms
  has_many :enrollments, dependent: :destroy
  has_many :users, through: :enrollments
  has_one :final_exam, dependent: :destroy

  validates :crn, uniqueness: { scope: :term_id, message: "has already been taken for this term" }, allow_nil: true

  after_destroy :update_term_dates
  after_save :update_term_dates, if: -> { saved_change_to_start_date? || saved_change_to_end_date? }

  enum :status, { active: "active", cancelled: "cancelled" }
  enum :schedule_type, Course::ScheduleType::TYPES.transform_values { |v| v[:code] }

  def schedule_type_description
    return nil unless schedule_type

    Course::ScheduleType.new(schedule_type).readable_description
  end

  def prefix
    subject =~ /\(([^)]+)\)/ ? $1 : subject
  end

  # Banner writes linked sections as <slot><key>. The slot says what the section
  # is for within the pairing, and the key says which pairing it belongs to. In
  # CHEM 1000 the lecture "A1" goes with the labs "B1", and the lecture "A2"
  # with the labs "B2".
  def link_slot
    link_identifier&.first
  end

  def link_key
    link_identifier.presence && link_identifier[1..].presence
  end

  # Sections a student has to register alongside this one: same course, same
  # link key, a different slot. Returns none when the section is not linked.
  def linked_sections
    return Course.none if link_key.blank?

    Course.active
          .where(term_id: term_id, subject: subject, course_number: course_number)
          .where("SUBSTRING(link_identifier FROM 2) = ?", link_key)
          .where.not(id: id)
          .where.not(link_identifier: nil)
          .where("LEFT(link_identifier, 1) <> ?", link_slot)
  end

  # Returns deduplicated meeting times, preferring non-TBD locations when there are duplicates.
  def filtered_meeting_times
    mts = meeting_times.loaded? ? meeting_times : meeting_times.includes(rooms: :building)
    mts.group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
       .map do |_key, group|
         next group.first if group.size == 1

         non_tbd = group.reject { |mt| tbd_location?(mt) }
         non_tbd.any? ? non_tbd.first : group.first
       end
  end

  private

  def tbd_location?(meeting_time)
    room = meeting_time.room
    building = room&.building
    return true if building.nil? || room.nil?

    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase == "tbd" ||
      building.abbreviation&.downcase == "tbd" ||
      room.number.to_s == "0"
  end

  # Within a Term.with_deferred_date_updates block, accumulates which terms need
  # updating rather than running once per course save.
  def update_term_dates
    if (pending = Thread.current[Term::PENDING_DATE_UPDATES_KEY])
      pending[term_id] ||= term
    else
      term.update_dates_from_courses!
    end
  end
end
