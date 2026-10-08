# frozen_string_literal: true

# Changes the title, place, or time of a whole FriendMeeting (every
# occurrence), then starts the job that writes the change to the provider
# events. The ICS feed shows the change at once.
#
# A key that the caller leaves out keeps its value. Raises
# FriendMeetingCreator::Error or ActiveRecord::RecordInvalid, like the
# creator.
class FriendMeetingUpdater < ApplicationService
  FIELDS = %i[title location start_time end_time].freeze

  def initialize(meeting:, changes:)
    @meeting = meeting
    @changes = changes.to_h.symbolize_keys.slice(*FIELDS)
  end

  def call
    raise FriendMeetingCreator::Error, "send at least one of #{FIELDS.join(', ')}" if @changes.empty?

    apply_changes
    return @meeting unless @meeting.changed?

    FriendMeeting.transaction do
      @meeting.save!
      @meeting.publications.calendars.update_all(status: "queued", last_error: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    FriendMeetingUpdateJob.perform_later(@meeting) if @meeting.publications.calendars.exists?
    @meeting
  end

  private

  def apply_changes
    @meeting.title    = @changes[:title].to_s.strip if @changes.key?(:title)
    @meeting.location = @changes[:location].to_s.strip.presence if @changes.key?(:location)
    @meeting.start_time = FriendMeetingCreator.parse_time(@changes[:start_time], "start_time") if @changes.key?(:start_time)
    @meeting.end_time   = FriendMeetingCreator.parse_time(@changes[:end_time], "end_time") if @changes.key?(:end_time)

    # A weekly meeting that moves to a new day can move to a new term.
    FriendMeetingCreator.assign_term(@meeting) if @meeting.weekly? && @meeting.start_time_changed?
  end
end
