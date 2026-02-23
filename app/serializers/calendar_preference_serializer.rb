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
#  index_calendar_prefs_on_user_scope_type  (user_id,scope,event_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class CalendarPreferenceSerializer
  include PreferenceSerializable

  def initialize(preference)
    @preference = preference
  end

  def as_json(*)
    {
      scope: @preference.scope,
      event_type: @preference.event_type,
      title_template: @preference.title_template,
      description_template: @preference.description_template,
      location_template: @preference.location_template,
      reminder_settings: transform_reminder_settings(@preference.reminder_settings),
      color_id: normalize_color_to_witcc_hex(@preference.color_id),
      visibility: @preference.visibility
    }
  end

end
