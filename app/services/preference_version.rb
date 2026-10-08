# frozen_string_literal: true

require "digest"

# Fingerprints preference inputs without resolving each meeting's templates.
# Include record identities and values so deletions and bulk writes also change
# the token; unrelated users and display-only settings cannot invalidate it.
class PreferenceVersion
  def self.for(user)
    fields = PreferenceResolver::PREFERENCE_FIELDS
    inputs = {
      user: user.id,
      events: user.event_preferences.order(:id).pluck(:id, :preferenceable_type, :preferenceable_id, *fields),
      calendars: user.calendar_preferences.order(:id).pluck(:id, :scope, :event_type, *fields),
      colors: UserExtensionConfig.where(user: user).pick(:default_color_lecture, :default_color_lab),
      notifications_disabled: user.notifications_disabled?,
      defaults: PreferenceResolver.defaults
    }

    Digest::SHA256.hexdigest(JSON.generate(inputs))
  end
end
