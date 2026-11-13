# frozen_string_literal: true

# == Schema Information
#
# Table name: registration_plans
#
#  id          :bigint           not null, primary key
#  courses     :jsonb            not null
#  preferences :jsonb            not null
#  term_uid    :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_registration_plans_on_term_uid              (term_uid)
#  index_registration_plans_on_user_id_and_term_uid  (user_id,term_uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_uid => terms.uid) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# The registration plan of one student for one term (#995): the courses and
# sections the student picks in the schedule builder of the extension. It is
# a help for planning, not a registration. A student registers in LeopardWeb.
#
# Each entry of courses has these keys, and no others:
#
#   { "code" => "COMP 3350", "crns" => ["20410", "20411"],
#     "fills" => { "kind" => "course", "label" => "Algorithms" } }
#
# fills is the plan row that the course fills, or nil for an extra course.
# preferences holds the answers of the schedule builder as the extension
# sends them. The backend does not read them. docs/academic-profile.md gives
# the limits below.
class RegistrationPlan < ApplicationRecord
  MAX_COURSES = 15
  MAX_CRNS_PER_COURSE = 4
  MAX_CODE_LENGTH = 20
  MAX_FILLS_KIND_LENGTH = 30
  MAX_FILLS_LABEL_LENGTH = 200
  MAX_PREFERENCES_BYTES = 2_048
  CRN_FORMAT = /\A\d{1,6}\z/

  belongs_to :user
  belongs_to :term, primary_key: :uid, foreign_key: :term_uid, inverse_of: false

  validates :term_uid, uniqueness: { scope: :user_id }
  validate :courses_are_valid
  validate :preferences_are_valid

  # Banner term codes sort by date, so the newest term has the largest uid.
  scope :newest_first, -> { order(term_uid: :desc) }
  scope :before_term, ->(term_uid) { where(term_uid: ...term_uid) }

  # Keeps only the keys of a course entry, and stores each CRN as a string
  # without leading zeros.
  # A value of the wrong type stays as it is, so the validation reports it.
  def courses=(value)
    super(value.is_a?(Array) ? value.map { |entry| clean_course(entry) } : value)
  end

  def preferences=(value)
    super(value.nil? ? {} : value)
  end

  # The CRNs of every course, in order, each one time.
  def crns
    Array(courses).flat_map { |course| course["crns"] }.uniq
  end

  def course_codes
    Array(courses).pluck("code")
  end

  def course_count
    Array(courses).size
  end

  # A fresh check of the CRNs: seats, conflicts, and cancelled sections. The
  # plan gives the term, so the check leaves it out.
  def schedule_check
    Catalog::ScheduleCheck.new(term_uid: term_uid, crns: crns).call.except(:term)
  end

  private

  def clean_course(entry)
    return entry unless entry.is_a?(Hash)

    entry = entry.stringify_keys.slice("code", "crns", "fills")
    entry["crns"] = entry["crns"].map { |crn| clean_crn(crn) } if entry["crns"].is_a?(Array)
    entry["fills"] = entry["fills"].stringify_keys.slice("kind", "label") if entry["fills"].is_a?(Hash)
    entry
  end

  # 20410, "20410", and "020410" are one CRN, as Catalog::ScheduleCheck
  # reads them. Each one is stored as "20410".
  def clean_crn(crn)
    crn = crn.to_s if crn.is_a?(Integer)
    crn.is_a?(String) && crn.match?(CRN_FORMAT) ? crn.to_i.to_s : crn
  end

  def courses_are_valid
    unless courses.is_a?(Array) && courses.size.between?(1, MAX_COURSES)
      return errors.add(:courses, "must be a list of 1 to #{MAX_COURSES} courses")
    end

    courses.each_with_index { |course, index| course_errors(course, index + 1) }
    return if errors.any? || crns.size <= Catalog::ScheduleCheck::MAX_CRNS

    errors.add(:courses, "can name at most #{Catalog::ScheduleCheck::MAX_CRNS} CRNs")
  end

  def course_errors(course, number)
    return errors.add(:courses, "entry #{number} must be an object") unless course.is_a?(Hash)

    code = course["code"]
    unless code.is_a?(String) && code.strip.present? && code.length <= MAX_CODE_LENGTH
      errors.add(:courses, "entry #{number} needs a code of at most #{MAX_CODE_LENGTH} characters")
    end

    crns = course["crns"]
    unless crns.is_a?(Array) && crns.size.between?(1, MAX_CRNS_PER_COURSE)
      return errors.add(:courses, "entry #{number} needs 1 to #{MAX_CRNS_PER_COURSE} CRNs")
    end

    errors.add(:courses, "entry #{number} has a CRN that is not digits") unless crns.all? { |crn| crn.is_a?(String) && crn.match?(CRN_FORMAT) }
    fills_errors(course["fills"], number)
  end

  def fills_errors(fills, number)
    return if fills.nil?

    kind  = fills["kind"] if fills.is_a?(Hash)
    label = fills["label"] if fills.is_a?(Hash)
    valid = kind.is_a?(String) && kind.present? && kind.length <= MAX_FILLS_KIND_LENGTH &&
            label.is_a?(String) && label.present? && label.length <= MAX_FILLS_LABEL_LENGTH
    return if valid

    errors.add(:courses, "entry #{number} needs fills with a kind of at most #{MAX_FILLS_KIND_LENGTH} " \
                         "characters and a label of at most #{MAX_FILLS_LABEL_LENGTH} characters, or null")
  end

  def preferences_are_valid
    return errors.add(:preferences, "must be an object") unless preferences.is_a?(Hash)
    return if preferences.to_json.bytesize <= MAX_PREFERENCES_BYTES

    errors.add(:preferences, "must be at most #{MAX_PREFERENCES_BYTES} bytes of JSON")
  end
end
