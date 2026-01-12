# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  event_type           :string
#  location_template    :text
#  reminder_settings    :jsonb
#  scope                :integer          not null
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  user_id              :bigint           not null
#
# Indexes
#
#  index_calendar_preferences_on_user_id    (user_id)
#  index_calendar_prefs_on_user_scope_type  (user_id,scope,event_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class CalendarPreference < ApplicationRecord
  include ReminderSettingsNormalizable
  include PublicIdentifiable

  set_public_id_prefix :cpf, min_hash_length: 12

  belongs_to :user

  # Enums
  enum :scope, {
    global: 0,
    event_type: 1,
    uni_cal_category: 2
  }, prefix: true

  # Valid university calendar categories (must match UniversityCalendarEvent::CATEGORIES)
  UNI_CAL_CATEGORIES = %w[holiday term_dates registration deadline finals graduation academic campus_event meeting exhibit announcement other].freeze

  # Validations
  validates :scope, presence: true
  validates :event_type, presence: true, if: -> { scope_event_type? || scope_uni_cal_category? }
  validates :event_type, absence: true, if: :scope_global?
  validates :event_type, inclusion: { in: UNI_CAL_CATEGORIES }, if: :scope_uni_cal_category?
  validates :title_template, length: { maximum: 500 }, allow_blank: true
  validates :description_template, length: { maximum: 2000 }, allow_blank: true
  validates :location_template, length: { maximum: 500 }, allow_blank: true
  validates :color_id, inclusion: { in: 1..11 }, allow_nil: true
  validates :visibility, inclusion: { in: %w[public private default] }, allow_blank: true
  validate :validate_template_syntax

  # Trigger calendar sync when preferences change that affect event appearance
  after_update :sync_calendar_if_preferences_changed

  # Scopes
  scope :for_event_type, ->(type) { where(scope: :event_type, event_type: type) }
  scope :for_uni_cal_category, ->(category) { where(scope: :uni_cal_category, event_type: category) }
  scope :global_scope, -> { where(scope: :global) }
  scope :uni_cal_categories_scope, -> { where(scope: :uni_cal_category) }

  private

  def validate_template_syntax
    if title_template.present?
      begin
        CalendarTemplateRenderer.validate_template(title_template)
      rescue CalendarTemplateRenderer::InvalidTemplateError => e
        errors.add(:title_template, "invalid syntax: #{e.message}")
      end
    end

    if description_template.present?
      begin
        CalendarTemplateRenderer.validate_template(description_template)
      rescue CalendarTemplateRenderer::InvalidTemplateError => e
        errors.add(:description_template, "invalid syntax: #{e.message}")
      end
    end

    return if location_template.blank?

    begin
      CalendarTemplateRenderer.validate_template(location_template)
    rescue CalendarTemplateRenderer::InvalidTemplateError => e
      errors.add(:location_template, "invalid syntax: #{e.message}")
    end
  end

  def sync_calendar_if_preferences_changed
    # Trigger forced sync if any template or display preferences changed
    if saved_change_to_title_template? ||
       saved_change_to_description_template? ||
       saved_change_to_location_template? ||
       saved_change_to_color_id? ||
       saved_change_to_visibility? ||
       saved_change_to_reminder_settings?
      # Force sync to update all existing events with new preferences
      GoogleCalendarSyncJob.perform_later(user, force: true)
    end
  end

end
