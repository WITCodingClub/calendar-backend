# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
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
#  color_id             :string
#  user_id              :bigint           not null
#
# Indexes
#
#  index_calendar_prefs_on_user_scope_type   (user_id,scope,event_type) UNIQUE
#  index_calendar_prefs_one_global_per_user  (user_id) UNIQUE WHERE (scope = 0)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class CalendarPreference < ApplicationRecord
  include PreferenceFields
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :cpf, min_hash_length: 12

  belongs_to :user

  UNI_CAL_CATEGORIES = UniversityCalendarEvent::CATEGORIES

  enum :scope, { global: 0, event_type: 1, uni_cal_category: 2, uni_cal_global: 3 }, prefix: true

  validates :scope, presence: true
  # The unique index does not catch a repeat of a scope that has no event_type,
  # because Postgres treats each NULL as distinct.
  validates :scope, uniqueness: { scope: [ :user_id, :event_type ] }
  validates :event_type, presence: true, if: -> { scope_event_type? || scope_uni_cal_category? }
  validates :event_type, absence: true, if: -> { scope_global? || scope_uni_cal_global? }
  validates :event_type, inclusion: { in: UNI_CAL_CATEGORIES }, if: :scope_uni_cal_category?

  after_update_commit :sync_calendar_if_preferences_changed
  # A category row sits above the university wide row in Preferences::Resolver, so
  # a category color from an old extension build hides the color the person
  # picks now. A save that picks a university wide color ends those overrides,
  # also when the color is the same, because an old build can write category
  # colors again between two saves. A save that does not set the color, such
  # as a visibility change, keeps them.
  after_save :clear_category_colors, if: :university_wide_color_picked?
  after_save { @color_id_picked = false }

  # Dirty tracking cannot see an assignment of the value the row already has,
  # so the writer records each assignment (university_wide_color_picked?).
  def color_id=(value)
    @color_id_picked = true
    super
  end

  scope :for_event_type,       ->(type) { where(scope: :event_type, event_type: type) }
  scope :for_uni_cal_category, ->(cat) { where(scope: :uni_cal_category, event_type: cat) }
  scope :global_scope,         -> { where(scope: :global) }
  scope :for_uni_cal_category_scope, -> { where(scope: :uni_cal_category) }
  scope :uni_cal_global_scope, -> { where(scope: :uni_cal_global) }

  private

  def university_wide_color_picked?
    scope_uni_cal_global? && color_id.present? && (@color_id_picked || saved_change_to_color_id?)
  end

  def clear_category_colors
    # No sync is queued here: every controller that saves a preference queues
    # a forced sync after the save, also when no field changed.
    user.calendar_preferences.for_uni_cal_category_scope.where.not(color_id: nil)
        .update_all(color_id: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def sync_calendar_if_preferences_changed
    return unless preference_fields_changed?

    CourseCalendars::SyncJob.perform_later(user, force: true)
  end
end
