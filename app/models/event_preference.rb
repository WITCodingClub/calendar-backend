# frozen_string_literal: true

# == Schema Information
#
# Table name: event_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  location_template    :text
#  preferenceable_type  :string           not null
#  reminder_settings    :jsonb
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  preferenceable_id    :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_event_preferences_on_preferenceable     (preferenceable_type,preferenceable_id)
#  index_event_preferences_on_user_id            (user_id)
#  index_event_prefs_on_preferenceable           (preferenceable_type,preferenceable_id)
#  index_event_prefs_on_user_and_preferenceable  (user_id,preferenceable_type,preferenceable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class EventPreference < ApplicationRecord
  include ReminderSettingsNormalizable
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :epf, min_hash_length: 12

  belongs_to :user
  belongs_to :preferenceable, polymorphic: true

  # Validations
  validates :title_template, length: { maximum: 500 }, allow_blank: true
  validates :description_template, length: { maximum: 2000 }, allow_blank: true
  validates :location_template, length: { maximum: 500 }, allow_blank: true
  validates :color_id, inclusion: { in: 1..11 }, allow_nil: true
  validates :visibility, inclusion: { in: %w[public private default] }, allow_blank: true
  validate :validate_template_syntax
  validate :at_least_one_preference_set

  # Scopes
  scope :for_meeting_times, -> { where(preferenceable_type: "MeetingTime") }
  scope :for_google_calendar_events, -> { where(preferenceable_type: "GoogleCalendarEvent") }

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

  def at_least_one_preference_set
    # Note: reminder_settings uses .nil? instead of .blank? because an empty array []
    # is a valid preference (it means "no notifications"), not an unset field
    return unless title_template.blank? && description_template.blank? && location_template.blank? && reminder_settings.nil? && color_id.blank? && visibility.blank?

    errors.add(:base, "At least one preference must be set")

  end

end
