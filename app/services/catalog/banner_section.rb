# frozen_string_literal: true

module Catalog
  # One section as Banner describes it, in the form the courses table stores.
  # Banner describes a section in two answers with different key names: the
  # class search (500 sections in one request: Catalog::Importer,
  # Catalog::SeatRefresh) and getClassDetails (one section:
  # Catalog::SectionSync, Courses::Processor). Every rule that turns either
  # answer into column values is here, so the callers read symbols only.
  class BannerSection
    # Each pair is written together or not at all: the database checks that
    # the available count is not more than the capacity, and half a count
    # means nothing. An over-enrolled section reports a negative number of
    # seats (about 17% do), and it is kept: clamping to 0 makes it read as
    # full.
    COUNT_PAIRS = {
      seats:      %i[seats_capacity seats_available],
      waitlist:   %i[waitlist_capacity waitlist_available],
      cross_list: %i[cross_list_capacity cross_list_available]
    }.freeze

    SEARCH_COUNT_KEYS = {
      seats:      %w[maximumEnrollment seatsAvailable],
      waitlist:   %w[waitCapacity waitAvailable],
      cross_list: %w[crossListCapacity crossListAvailable]
    }.freeze

    # Every column the counts can write, with the identifier of the
    # cross-list group that the cross-list counts belong to.
    CROSS_LIST_COLUMNS = [ :cross_list_identifier, *COUNT_PAIRS[:cross_list] ].freeze
    COUNT_COLUMNS = (COUNT_PAIRS.except(:cross_list).values.flatten + CROSS_LIST_COLUMNS).freeze

    DEFAULT_TITLE = "Untitled Course"

    # How Banner and the extension write a meeting day that is on.
    TRUE_VALUES = [ true, "true", "TRUE", "Y", "y", 1, "1" ].freeze

    attr_reader :crn, :term_uid, :schedule_type_text, :counts, :meeting_times, :faculty, :attributes

    def initialize(crn:, term_uid:, schedule_type_text:, counts:, meeting_times:, faculty:, attributes:)
      @crn = crn
      @term_uid = term_uid
      @schedule_type_text = schedule_type_text
      @counts = counts
      @meeting_times = meeting_times
      @faculty = faculty
      @attributes = attributes
    end

    # A class search result. Its meetings are deduplicated: Banner lists a
    # meeting once for each instructor.
    def self.from_search(data)
      new(
        crn: data["courseReferenceNumber"] || data["crn"],
        term_uid: data["term"] || data["termEffective"],
        schedule_type_text: data["scheduleTypeDescription"] || data["scheduleType"],
        counts: search_counts(data),
        meeting_times: Meeting.dedupe(Array(data["meetingsFaculty"]).filter_map { |session| session["meetingTime"].presence }
                                                                    .map { |mt| Meeting.from_search(mt) }),
        faculty: data["faculty"] || [],
        attributes: search_attributes(data)
      )
    end

    # The hash of Catalog::LeopardWebClient.get_class_details.
    #
    # Credit hours are not taken from getClassDetails. Its "Credit Hours" is
    # the course's credits, so it gives a lab the lecture's 4. The class
    # search gives the section's own credits (see search_attributes).
    def self.from_class_details(details)
      new(
        crn: details[:crn],
        term_uid: nil,
        schedule_type_text: details[:schedule_type],
        counts: pair(:seats, details[:seats_capacity], details[:seats_available])
                  .merge(pair(:waitlist, details[:waitlist_capacity], details[:waitlist_available])),
        meeting_times: Array(details[:meeting_times]).map { |mt| Meeting.from_class_details(mt) },
        faculty: details[:faculty] || [],
        attributes: {
          title: details[:title].to_s.strip.presence,
          grade_mode: details[:grade_mode]&.strip,
          subject: details[:subject]&.strip,
          section_number: details[:section_number] && SectionNumber.normalize(details[:section_number])
        }.compact
      )
    end

    # The cross-list counts are the group's seats, so they go with the group
    # identifier: a section that left its group has neither, and a group with
    # half a count is not written.
    def self.search_counts(data)
      counts = SEARCH_COUNT_KEYS.except(:cross_list).map { |name, keys| pair(name, *data.values_at(*keys)) }.reduce({}, :merge)
      return counts.merge(CROSS_LIST_COLUMNS.index_with(nil)) if data["crossList"].blank?

      group = pair(:cross_list, *data.values_at(*SEARCH_COUNT_KEYS[:cross_list]))
      group.empty? ? counts : counts.merge(group, cross_list_identifier: data["crossList"])
    end

    def self.pair(name, capacity, available)
      return {} if capacity.nil? || available.nil?

      COUNT_PAIRS.fetch(name).zip([ capacity.to_i, available.to_i ]).to_h
    end

    # The enum key of Banner's schedule type, "Lecture (LEC)" or "LEC", or nil
    # when Banner sends text with no known code, such as "No Section
    # specified schedule type, ...".
    def self.schedule_type_key(text)
      return nil if text.blank?

      match = text.to_s.match(/\(([^)]+)\)/)
      Course::ScheduleType.key_for_code(match ? match[1].strip : text.to_s.strip)
    end

    # Banner sends creditHours for current terms, but older terms (2022 and
    # 2023) send it as null and put the fixed value in creditHourLow. A
    # section linked to a lecture, such as a lab, reports 0, and the lecture
    # carries the credits. Some labs stand alone and carry credits (ARCH
    # studios are 6), so the schedule type does not decide this. Store nil
    # for 0.
    def self.search_credit_hours(data)
      hours = data["creditHours"]
      hours = data["creditHourLow"] if hours.nil? && data["creditHourIndicator"].blank?
      hours.to_i.positive? ? hours.to_i : nil
    end

    # Banner says which sections must be taken together (linkIdentifier).
    # Inferring the pairing from the sequence number works most of the time,
    # but this is the registrar's own answer.
    #
    # The part of term is "1" for the full term, or a code such as "FA1" or
    # "FA2" for one half. A cross-list group joins sections of different
    # courses that meet together, such as an undergraduate and a graduate
    # ARCH studio. Its identifier is unique only in its term, and the seats
    # count the whole group.
    def self.search_attributes(data)
      {
        title: data["courseTitle"] || DEFAULT_TITLE,
        subject_description: CGI.unescapeHTML(data["subjectDescription"].to_s),
        subject_code: data["subject"] || data["subjectCode"],
        course_number: data["courseNumber"],
        section_number: SectionNumber.normalize(data["sequenceNumber"] || data["sectionNumber"]),
        credit_hours: search_credit_hours(data),
        link_identifier: data["linkIdentifier"].presence,
        is_section_linked: ActiveModel::Type::Boolean.new.cast(data["isSectionLinked"]) || false,
        part_of_term: data["partOfTerm"].presence,
        campus: CGI.unescapeHTML(data["campusDescription"].to_s).presence
      }
    end
    private_class_method :search_attributes, :search_credit_hours, :search_counts

    def schedule_type
      self.class.schedule_type_key(schedule_type_text)
    end
  end
end
