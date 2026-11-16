# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_credits
#
#  id         :bigint           not null, primary key
#  code       :string           not null
#  credits    :integer
#  kind       :string
#  source     :string           not null
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_transfer_credits_on_user_id_and_code  (user_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# One AP, test, or transfer credit of a student (#1020), with the WIT course
# it counts as. DegreeProgress counts it as a done course with no term.
#
# source transcript: the extension read it from the transfer credit section
# of the LeopardWeb Academic Transcript. Each sync replaces these rows
# (AcademicProfiles::TransferCredits#replace_transcript), so a student cannot
# delete one. source student: the student added it by hand, because the
# transcript does not list it.
#
# code is a WIT course code, stored as "ENGL 1100".
class TransferCredit < ApplicationRecord
  SOURCES = { transcript: "transcript", student: "student" }.freeze
  KINDS = { ap: "ap", transfer: "transfer", test: "test" }.freeze
  MAX_TITLE_LENGTH = 200
  MAX_CREDITS = 30

  enum :source, SOURCES, validate: true
  enum :kind, KINDS, validate: { allow_nil: true }, prefix: true

  belongs_to :user

  normalizes :code, with: ->(code) { CourseCode.normalize(code) || code.to_s.strip }

  validates :code, presence: true, uniqueness: { scope: :user_id }
  validates :title, length: { maximum: MAX_TITLE_LENGTH }
  validates :credits, numericality: { only_integer: true, in: 0..MAX_CREDITS }, allow_nil: true
  validate :code_is_a_course_code

  def key = CourseCode.parse(code)

  private

  def code_is_a_course_code
    errors.add(:code, "must be a course code such as ENGL 1100") if code.present? && key.nil?
  end
end
