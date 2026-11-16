# frozen_string_literal: true

module FriendMeetings
  # How a meeting repeats: frequency, interval (every N days, weeks, or
  # months), days (the weekdays of a weekly meeting), and until (the last
  # date, or nil for the end of the term). FriendMeetings::Creator and
  # FriendMeetings::Updater build one and apply it to the meeting.
  RepeatOptions = Data.define(:frequency, :interval, :days, :until) do
    def self.one_time = new(frequency: FriendMeeting::FREQUENCIES[:one_time], interval: 1, days: [], until: nil)

    # A one-time meeting takes no repeat option.
    def self.check_one_time!(interval, days, until_value)
      return unless [ interval, days, until_value ].any?(&:present?)

      raise Error, "repeat_interval, repeat_days, and repeat_until need a repeating frequency"
    end

    def one_time? = frequency == FriendMeeting::FREQUENCIES[:one_time]

    # Sets the options on the meeting. A repeating meeting belongs to the
    # term that holds its first day; between terms, that is the current term,
    # which must not have ended. Without until, it repeats to the term's end.
    def apply_to(meeting)
      meeting.assign_attributes(frequency: frequency, repeat_interval: interval, repeat_days: days)
      return meeting.assign_attributes(repeat_until: nil, term: nil) if one_time?

      start_date = meeting.local_start.to_date
      term       = Term.find_by_date(start_date) || Term.current
      if term.nil? || term.end_date.nil? || term.end_date < start_date
        raise Error, "a repeating meeting must start on or before the last day of the current term"
      end

      meeting.assign_attributes(term: term, repeat_until: self.until || term.end_date)
    end
  end
end
