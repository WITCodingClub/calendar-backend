# frozen_string_literal: true

# An old course code and the code that replaced it, such as COMP128 and
# COMP1000. Wentworth gave most courses 4-digit numbers in 2015-2016, and no
# catalog lists the old and new numbers. A plan in an old catalog names the
# old code, so a student who took the new course still meets it.
#
# `source` says how the row was found: the same subject and title in two
# catalog years (`title_match`), Banner sections (`banner`), or a person
# (`admin`). reviewed_at is set when a person checks the row.
# == Schema Information
#
# Table name: course_code_aliases
#
#  id                 :bigint           not null, primary key
#  from_course_number :integer          not null
#  from_subject_code  :string           not null
#  note               :string
#  reviewed_at        :datetime
#  source             :string           not null
#  to_course_number   :integer          not null
#  to_subject_code    :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  idx_course_code_aliases_unique                      (from_subject_code,from_course_number,to_subject_code,to_course_number) UNIQUE
#  idx_on_to_subject_code_to_course_number_49e737555f  (to_subject_code,to_course_number)
#
class CourseCodeAlias < ApplicationRecord
  SOURCES = { title_match: "title_match", banner: "banner", admin: "admin" }.freeze

  enum :source, SOURCES, validate: true, prefix: true

  scope :reviewed, -> { where.not(reviewed_at: nil) }

  before_validation do
    self.from_subject_code = from_subject_code&.strip&.upcase.presence
    self.to_subject_code = to_subject_code&.strip&.upcase.presence
  end

  validates :from_subject_code, :from_course_number, :to_subject_code, :to_course_number, presence: true
  validates :to_course_number, uniqueness: { scope: [ :from_subject_code, :from_course_number, :to_subject_code ] }
  validate :codes_differ
  validate :no_reverse_alias

  def from_code = "#{from_subject_code} #{from_course_number}"
  def to_code = "#{to_subject_code} #{to_course_number}"

  private

  def codes_differ
    errors.add(:to_course_number, "must name a different course") if from_code == to_code
  end

  # A pair in both directions would send a lookup that follows the aliases
  # around in a loop.
  def no_reverse_alias
    reverse = self.class.where(from_subject_code: to_subject_code, from_course_number: to_course_number,
                               to_subject_code: from_subject_code, to_course_number: from_course_number)
    errors.add(:base, "#{to_code} already points to #{from_code}") if reverse.where.not(id: id).exists?
  end
end
