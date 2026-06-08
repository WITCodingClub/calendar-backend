# frozen_string_literal: true

class Course < ApplicationRecord
  include CourseChangeTrackable
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :crs

  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, class_name: "Course::MeetingTime", dependent: :destroy
  has_many :rooms, through: :meeting_times
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

  # Returns deduplicated meeting times, preferring non-TBD locations when there are duplicates.
  def filtered_meeting_times
    meeting_times.includes(room: :building).group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
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
