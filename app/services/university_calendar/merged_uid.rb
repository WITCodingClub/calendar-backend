# frozen_string_literal: true

module UniversityCalendar
  # The feed lists a break of several days as one event per day.
  # UniversityCalendar::IcsImport stores the run as one event, and its ics_uid
  # names the first feed uid and the count: "merged:<first uid>+<count>". A
  # cancel or a later import finds the stored event by that first uid.
  module MergedUid
    PATTERN = /\Amerged:(?<root>.+)\+\d+\z/

    module_function

    def for(uids) = uids.one? ? uids.first : "merged:#{uids.first}+#{uids.size}"

    # The first feed uid of a merged ics_uid, or nil for any other uid.
    def root(ics_uid) = ics_uid.to_s.match(PATTERN)&.[](:root)
  end
end
