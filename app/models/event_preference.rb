# frozen_string_literal: true

# == Schema Information
#
# Table name: event_preferences
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
#  color_id             :string
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
class EventPreference < ApplicationRecord
  include PreferenceFields
  include EncodedIds::HashidIdentifiable
  include ResyncsCalendar

  set_public_id_prefix :epf, min_hash_length: 12

  belongs_to :user
  belongs_to :preferenceable, polymorphic: true

  validate :at_least_one_preference_set

  scope :for_meeting_times, -> { where(preferenceable_type: "Course::MeetingTime") }

  private

  def calendar_changed?
    previously_new_record? || preference_fields_changed?
  end

  def at_least_one_preference_set
    errors.add(:base, "At least one preference must be set") unless any_preference_set?
  end
end
