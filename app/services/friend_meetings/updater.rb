# frozen_string_literal: true

module FriendMeetings
  # Changes the title, place, time, or repeat options of a whole FriendMeeting
  # (every occurrence), then starts the job that writes the change to the
  # provider events. The ICS feed shows the change at once.
  #
  # A key that the caller leaves out keeps its value. A repeat_until of nil
  # (or "") goes back to the end of the term. A frequency of one_time stops
  # the repeats and clears the repeat options. Raises
  # FriendMeetings::Creator::Error or ActiveRecord::RecordInvalid, like the
  # creator.
  class Updater < ApplicationService
    REPEAT_FIELDS = %i[frequency repeat_interval repeat_days repeat_until].freeze
    FIELDS        = (%i[title location start_time end_time] + REPEAT_FIELDS).freeze
    # For params.permit: repeat_days is a list.
    PERMITTED = (FIELDS - [ :repeat_days ] + [ { repeat_days: [] } ]).freeze

    def initialize(meeting:, changes:)
      @meeting = meeting
      @changes = changes.to_h.symbolize_keys.slice(*FIELDS)
    end

    def call
      raise FriendMeetings::Creator::Error, "send at least one of #{FIELDS.join(', ')}" if @changes.empty?

      apply_changes
      return @meeting unless @meeting.changed?

      FriendMeeting.transaction do
        @meeting.save!
        @meeting.publications.calendars.update_all(status: "queued", last_error: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      FriendMeetings::UpdateJob.perform_later(@meeting) if @meeting.publications.calendars.exists?
      @meeting
    end

    private

    def apply_changes
      @meeting.title    = @changes[:title].to_s.strip if @changes.key?(:title)
      @meeting.location = @changes[:location].to_s.strip.presence if @changes.key?(:location)
      @meeting.start_time = FriendMeetings::Creator.parse_time(@changes[:start_time], "start_time") if @changes.key?(:start_time)
      @meeting.end_time   = FriendMeetings::Creator.parse_time(@changes[:end_time], "end_time") if @changes.key?(:end_time)

      if @changes.keys.intersect?(REPEAT_FIELDS)
        apply_repeat_changes
      elsif @meeting.repeating? && @meeting.start_time_changed?
        FriendMeetings::Creator.assign_term(@meeting, repeat_until: picked_repeat_until)
      end
    end

    def apply_repeat_changes
      frequency = @changes.key?(:frequency) ? @changes[:frequency].presence || "one_time" : @meeting.frequency
      FriendMeetings::Creator.check_frequency(frequency)

      if frequency == FriendMeeting::FREQUENCIES[:one_time]
        if %i[repeat_interval repeat_days repeat_until].any? { |key| @changes[key].present? }
          raise FriendMeetings::Creator::Error, FriendMeetings::Creator::REPEAT_OPTIONS_NEED_FREQUENCY
        end

        @meeting.assign_attributes(frequency: frequency, repeat_interval: 1, repeat_days: [], repeat_until: nil, term: nil)
        return
      end

      was_repeating = @meeting.repeating?
      repeat_until  = @changes.key?(:repeat_until) ? FriendMeetings::Creator.parse_date(@changes[:repeat_until], "repeat_until") : picked_repeat_until

      @meeting.repeat_interval = new_interval(was_repeating)
      @meeting.repeat_days     = new_days(frequency)
      @meeting.frequency       = frequency
      FriendMeetings::Creator.assign_term(@meeting, repeat_until: repeat_until)
    end

    # A one-time meeting that starts to repeat starts at an interval of 1.
    def new_interval(was_repeating)
      return FriendMeetings::Creator.parse_interval(@changes[:repeat_interval]) if @changes.key?(:repeat_interval)

      was_repeating ? @meeting.repeat_interval : 1
    end

    # The days stay only while the meeting stays weekly.
    def new_days(frequency)
      return FriendMeetings::Creator.parse_days(@changes[:repeat_days]) if @changes.key?(:repeat_days)

      @meeting.weekly? && frequency == FriendMeeting::FREQUENCIES[:weekly] ? @meeting.repeat_days : []
    end

    # The repeat_until that the person picked, or nil when the meeting repeats
    # until the end of its term. A repeating meeting that moves to a new day
    # can move to a new term, and a nil keeps it to the end of that term.
    def picked_repeat_until
      return nil unless @meeting.repeating?

      @meeting.repeat_until unless @meeting.repeat_until == @meeting.term&.end_date
    end
  end
end
