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
#  index_event_prefs_on_user_and_preferenceable  (user_id,preferenceable_type,preferenceable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class EventPreferenceSerializer
  include PreferenceSerializable

  def initialize(preference)
    @preference = preference
  end

  def as_json(*)
    {
      title_template: @preference.title_template,
      description_template: @preference.description_template,
      location_template: @preference.location_template,
      reminder_settings: transform_reminder_settings(@preference.reminder_settings),
      color_id: normalize_color_to_witcc_hex(@preference.color_id),
      visibility: @preference.visibility
    }
  end

end
