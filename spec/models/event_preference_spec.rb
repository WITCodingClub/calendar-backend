# frozen_string_literal: true

require "rails_helper"

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
#  color_id             :integer
#  preferenceable_id    :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_event_preferences_on_preferenceable     (preferenceable_type,preferenceable_id)
#  index_event_preferences_on_user_id            (user_id)
#  index_event_prefs_on_user_and_preferenceable  (user_id,preferenceable_type,preferenceable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe EventPreference, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:preferenceable) }

  it { is_expected.to validate_length_of(:title_template).is_at_most(500).allow_blank }
  it { is_expected.to validate_length_of(:description_template).is_at_most(2000).allow_blank }
  it { is_expected.to validate_length_of(:location_template).is_at_most(500).allow_blank }
  it { is_expected.to validate_inclusion_of(:color_id).in_range(1..11).allow_nil }
  it { is_expected.to validate_inclusion_of(:visibility).in_array(%w[public private default]).allow_blank }

  # #at_least_one_preference_set is a custom, cross-field validation (title,
  # description, location, reminder_settings, color_id, and visibility can
  # satisfy each other), so there's no single attribute for
  # validate_presence_of to point at.
end
