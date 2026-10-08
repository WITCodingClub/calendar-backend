# frozen_string_literal: true

# The user's settings for one class: how its assignments go to the calendar,
# and how its grade is counted. A nil column inherits the default, the same
# way as calendar and event preferences.
# == Schema Information
#
# Table name: brightspace_class_preferences
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  grade_categories     :jsonb
#  grade_mode           :string
#  included_kinds       :string           is an Array
#  location_template    :text
#  reminder_settings    :jsonb
#  sync_enabled         :boolean
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :string
#  course_offering_id   :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_brightspace_class_preferences_on_course_offering_id  (course_offering_id) UNIQUE
#  index_brightspace_class_preferences_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
module Brightspace
  class ClassPreference < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include ReminderSettingsNormalizable
    include Brightspace::VersionBumping

    set_public_id_prefix :bcp, min_hash_length: 12

    GRADE_MODES = %w[brightspace syllabus custom].freeze
    DEFAULT_GRADE_MODE = "brightspace"

    belongs_to :user
    belongs_to :course_offering, class_name: "Brightspace::CourseOffering", inverse_of: :preference

    validates :course_offering_id, uniqueness: true
    validates :grade_mode, inclusion: { in: GRADE_MODES }, allow_nil: true
    validates :title_template, length: { maximum: 500 }, allow_blank: true
    validates :description_template, length: { maximum: 2000 }, allow_blank: true
    validates :location_template, length: { maximum: 500 }, allow_blank: true
    normalizes :color_id, with: GoogleColors.method(:normalize_attribute)
    validates :color_id, format: { with: GoogleColors::HEX_FORMAT }, allow_nil: true
    validates :visibility, inclusion: { in: %w[public private default] }, allow_blank: true
    validate :included_kinds_are_known
    validate :template_syntax
    validate :grade_categories_format
    validate :course_offering_belongs_to_user

    def effective_sync_enabled = sync_enabled.nil? ? true : sync_enabled
    def effective_included_kinds = included_kinds.nil? ? Brightspace::Assignment::KINDS : included_kinds
    def effective_grade_mode = grade_mode || DEFAULT_GRADE_MODE

    private

    # included_kinds is a Postgres array, which no inclusion matcher covers.
    def included_kinds_are_known
      return if included_kinds.nil?

      unknown = included_kinds - Brightspace::Assignment::KINDS
      errors.add(:included_kinds, "has an unknown kind: #{unknown.first}") if unknown.any?
    end

    def template_syntax
      %i[title_template description_template location_template].each do |field|
        value = public_send(field)
        next if value.blank?

        CalendarTemplateRenderer.validate_template(value)
      rescue CalendarTemplateRenderer::InvalidTemplateError => e
        errors.add(field, "invalid syntax: #{e.message}")
      end
    end

    # The rules must name categories and items of this class.
    def grade_categories_format
      Brightspace::GradeRules.errors_for(grade_categories, course_offering).each do |message|
        errors.add(:grade_categories, message)
      end
    end

    def course_offering_belongs_to_user
      return if course_offering.nil? || user.nil?

      errors.add(:course_offering, "is not one of your classes") unless course_offering.connection.user_id == user_id
    end
  end
end
