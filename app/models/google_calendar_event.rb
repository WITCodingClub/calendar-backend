# frozen_string_literal: true

class GoogleCalendarEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :gce, min_hash_length: 12

  belongs_to :google_calendar
  belongs_to :meeting_time, class_name: "Course::MeetingTime", optional: true
  belongs_to :final_exam, optional: true
  belongs_to :university_calendar_event, optional: true
  has_one :event_preference, as: :preferenceable, dependent: :destroy
  has_one :oauth_credential, through: :google_calendar
  has_one :user, through: :oauth_credential

  validates :google_event_id, presence: true
  validate :only_one_event_type_associated
  validates :meeting_time_id, uniqueness: { scope: :google_calendar_id }, if: :meeting_time_id?
  validates :final_exam_id, uniqueness: { scope: :google_calendar_id }, if: :final_exam?
  validates :university_calendar_event_id, uniqueness: { scope: :google_calendar_id }, if: :university_event?

  serialize :recurrence, coder: JSON

  TRACKABLE_FIELDS = %w[summary location description start_time end_time].freeze

  scope :for_meeting_time,           ->(id) { where(meeting_time_id: id) }
  scope :for_final_exam,             ->(id) { where(final_exam_id: id) }
  scope :for_university_event,       ->(id) { where(university_calendar_event_id: id) }
  scope :stale,                      ->(t = 1.hour) { where("last_synced_at IS NULL OR last_synced_at < ?", t.ago) }
  scope :recently_synced,            -> { where("last_synced_at > ?", 5.minutes.ago) }
  scope :finals_only,                -> { where.not(final_exam_id: nil) }
  scope :courses_only,               -> { where.not(meeting_time_id: nil) }
  scope :university_events_only,     -> { where.not(university_calendar_event_id: nil) }
  scope :user_edited,                -> { where.not(user_edited_fields: nil) }
  scope :not_user_edited,            -> { where(user_edited_fields: nil) }
  scope :orphaned,                   -> { where(meeting_time_id: nil, final_exam_id: nil, university_calendar_event_id: nil) }

  def final_exam?     = final_exam_id.present?
  def meeting_time?   = meeting_time_id.present?
  def university_event? = university_calendar_event_id.present?
  def orphaned?       = meeting_time_id.nil? && final_exam_id.nil? && university_calendar_event_id.nil?

  def syncable
    meeting_time || final_exam || university_calendar_event
  end

  def self.generate_data_hash(event_data)
    hash_input = [
      event_data[:summary],
      event_data[:location],
      event_data[:start_time]&.to_i,
      event_data[:end_time]&.to_i,
      event_data[:recurrence]&.to_json,
      event_data[:reminder_settings]&.to_json,
      event_data[:color_id]&.to_s,
      event_data[:visibility],
      event_data[:all_day]
    ].join("|")

    Digest::SHA256.hexdigest(hash_input)
  end

  def data_changed?(new_event_data)
    event_data_hash != self.class.generate_data_hash(new_event_data)
  end

  def update_data_hash!(event_data)
    update_column(:event_data_hash, self.class.generate_data_hash(event_data)) # rubocop:disable Rails/SkipsModelValidations
  end

  def mark_synced!
    update_columns(last_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def needs_sync?(threshold = 1.hour)
    last_synced_at.nil? || last_synced_at < threshold.ago
  end

  def user_edited?
    user_edited_fields.present? && user_edited_fields.any?
  end

  def field_edited?(field)
    user_edited_fields&.include?(field.to_s)
  end

  def mark_fields_edited!(fields)
    current_fields = user_edited_fields || []
    new_fields = (current_fields + Array(fields).map(&:to_s)).uniq & TRACKABLE_FIELDS
    update_columns(user_edited_fields: new_fields) # rubocop:disable Rails/SkipsModelValidations
  end

  def clear_edited_fields!(fields = nil)
    if fields.nil?
      update_columns(user_edited_fields: nil) # rubocop:disable Rails/SkipsModelValidations
    else
      remaining = (user_edited_fields || []) - Array(fields).map(&:to_s)
      update_columns(user_edited_fields: remaining.empty? ? nil : remaining) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def only_one_event_type_associated
    event_types = [ meeting_time_id, final_exam_id, university_calendar_event_id ].compact
    return unless event_types.size != 1

    errors.add(:base, "Must be associated with exactly one of: meeting_time, final_exam, or university_calendar_event")
  end
end
