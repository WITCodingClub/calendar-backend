# frozen_string_literal: true

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
