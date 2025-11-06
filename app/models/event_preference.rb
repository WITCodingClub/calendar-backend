# == Schema Information
#
# Table name: event_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
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
  belongs_to :user
  belongs_to :preferenceable, polymorphic: true

  # Validations
  validates :title_template, length: { maximum: 500 }, allow_blank: true
  validates :description_template, length: { maximum: 2000 }, allow_blank: true
  validates :color_id, inclusion: { in: 1..11 }, allow_nil: true
  validates :visibility, inclusion: { in: %w[public private default] }, allow_blank: true
  validate :validate_template_syntax
  validate :validate_reminder_settings_format
  validate :at_least_one_preference_set

  # Scopes
  scope :for_meeting_times, -> { where(preferenceable_type: 'MeetingTime') }
  scope :for_google_calendar_events, -> { where(preferenceable_type: 'GoogleCalendarEvent') }

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
  end

  def validate_reminder_settings_format
    return if reminder_settings.blank?

    unless reminder_settings.is_a?(Array)
      errors.add(:reminder_settings, "must be an array")
      return
    end

    reminder_settings.each_with_index do |reminder, index|
      unless reminder.is_a?(Hash)
        errors.add(:reminder_settings, "item #{index} must be a hash")
        next
      end

      unless reminder.key?("minutes") && reminder["minutes"].is_a?(Integer)
        errors.add(:reminder_settings, "item #{index} must have integer 'minutes' field")
      end

      unless reminder.key?("method") && %w[popup email].include?(reminder["method"])
        errors.add(:reminder_settings, "item #{index} must have 'method' field (popup or email)")
      end
    end
  end

  def at_least_one_preference_set
    if title_template.blank? && description_template.blank? && reminder_settings.blank? && color_id.blank? && visibility.blank?
      errors.add(:base, "At least one preference must be set")
    end
  end
end
