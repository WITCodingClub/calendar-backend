# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  event_type           :string
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
  belongs_to :user

  # Enums
  enum :scope, {
    global: 0,
    event_type: 1
  }, prefix: true

  # Validations
  validates :scope, presence: true
  validates :event_type, presence: true, if: :scope_event_type?
  validates :event_type, absence: true, if: :scope_global?
  validates :title_template, length: { maximum: 500 }, allow_blank: true
  validates :description_template, length: { maximum: 2000 }, allow_blank: true
  validates :color_id, inclusion: { in: 1..11 }, allow_nil: true
  validates :visibility, inclusion: { in: %w[public private default] }, allow_blank: true
  validate :validate_template_syntax
  validate :validate_reminder_settings_format

  # Scopes
  scope :for_event_type, ->(type) { where(scope: :event_type, event_type: type) }
  scope :global_scope, -> { where(scope: :global) }

  private

  def validate_template_syntax
    if title_template.present?
      begin
        CalendarTemplateRenderer.validate_template(title_template)
      rescue CalendarTemplateRenderer::InvalidTemplateError => e
        errors.add(:title_template, "invalid syntax: #{e.message}")
      end
    end

    return if description_template.blank?

    begin
      CalendarTemplateRenderer.validate_template(description_template)
    rescue CalendarTemplateRenderer::InvalidTemplateError => e
      errors.add(:description_template, "invalid syntax: #{e.message}")
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

end
