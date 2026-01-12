# frozen_string_literal: true

# Service to fetch and parse university calendar events from an ICS feed.
#
# This service:
# 1. Fetches the ICS feed from the configured URL
# 2. Parses the ICS events using the icalendar gem
# 3. Extracts custom fields (Organization, Academic Term, Event Type)
# 4. Creates or updates UniversityCalendarEvent records
# 5. Infers categories based on event content
#
# @example
#   result = UniversityCalendarIcsService.call
#   # => { created: 5, updated: 2, unchanged: 10, errors: [] }
#
class UniversityCalendarIcsService < ApplicationService
  ICS_FEED_URL = "https://25livepub.collegenet.com/calendars/wit-main-events-calendar.ics"

  attr_reader :ics_url

  def initialize(ics_url: ICS_FEED_URL)
    @ics_url = ics_url
    super()
  end

  def call
    Rails.logger.info("Fetching university calendar from: #{ics_url}")

    ics_content = fetch_ics_content
    events = parse_ics_events(ics_content)
    results = process_events(events)

    Rails.logger.info("University calendar sync complete: #{results}")
    results
  end

  private

  def fetch_ics_content
    # Convert webcal:// to https://
    url = ics_url.gsub(/^webcal:\/\//, "https://")

    response = Faraday.get(url) do |req|
      req.options.timeout = 30
      req.options.open_timeout = 10
    end

    unless response.success?
      raise "Failed to fetch ICS feed: #{response.status}"
    end

    response.body
  end

  def parse_ics_events(ics_content)
    calendars = Icalendar::Calendar.parse(ics_content)
    return [] if calendars.empty?

    calendar = calendars.first
    calendar.events
  end

  def process_events(ics_events)
    stats = { created: 0, updated: 0, unchanged: 0, errors: [] }

    ics_events.each do |ics_event|
      process_single_event(ics_event, stats)
    rescue => e
      stats[:errors] << "Error processing event #{ics_event.uid}: #{e.message}"
      Rails.logger.error("Failed to process ICS event: #{e.message}")
    end

    stats
  end

  def process_single_event(ics_event, stats)
    return if ics_event.dtstart.nil? # Skip events without start time

    # Extract and decode custom fields from X-TRUMBA-CUSTOMFIELD properties
    # Decode HTML entities early so decoded values are used consistently
    raw_custom_fields = extract_custom_fields(ics_event)
    organization = decode_html_entities(raw_custom_fields["Organization"])
    academic_term = decode_html_entities(raw_custom_fields["Academic Term"])
    event_type = decode_html_entities(raw_custom_fields["Event Type"])

    # Decode summary and location
    summary = decode_html_entities(ics_event.summary.to_s)
    location = decode_html_entities(ics_event.location&.to_s)

    # Find or initialize by ICS UID
    event = UniversityCalendarEvent.find_or_initialize_by(ics_uid: ics_event.uid.to_s)
    was_new = event.new_record?

    # Parse times
    start_time = parse_ics_time(ics_event.dtstart)
    end_time = parse_ics_time(ics_event.dtend || ics_event.dtstart)

    # Clean description (remove HTML tags)
    description = clean_description(ics_event.description&.to_s)

    # Infer category using decoded values
    category = UniversityCalendarEvent.infer_category(summary, event_type)

    # Determine if this should be an all-day event
    # Force holidays to be all-day regardless of ICS format
    is_all_day = category == "holiday" || all_day_event?(ics_event)

    # For all-day events, normalize times to beginning and end of day
    # but preserve original date range for multi-day events
    if is_all_day
      original_end_date = end_time.to_date
      start_time = start_time.beginning_of_day
      end_time = original_end_date.end_of_day
    end

    # Assign attributes (already decoded above)
    event.assign_attributes(
      summary: summary,
      description: description,
      location: location,
      start_time: start_time,
      end_time: end_time,
      all_day: is_all_day,
      recurrence: extract_recurrence(ics_event),
      category: category,
      organization: organization,
      academic_term: academic_term,
      event_type_raw: event_type,
      last_fetched_at: Time.current,
      source_url: ics_url
    )

    # Link to term if academic_term is specified
    if event.academic_term.present? && start_time
      event.term = find_term_from_academic_term(event.academic_term, start_time)
    end

    # Check if any field other than last_fetched_at has changed
    content_changed = event.changed? && (event.changed - ["last_fetched_at"]).any?

    if was_new || content_changed
      event.save!
      was_new ? stats[:created] += 1 : stats[:updated] += 1
    else
      # Just update the last_fetched_at timestamp
      event.update_column(:last_fetched_at, Time.current) if event.persisted?
      stats[:unchanged] += 1
    end
  end

  def extract_custom_fields(ics_event)
    fields = {}

    # icalendar gem stores custom properties with underscores replacing hyphens
    # and in lowercase. We need to handle X-TRUMBA-CUSTOMFIELD properties
    ics_event.custom_properties.each do |key, values|
      next unless key.to_s.start_with?("x_trumba_customfield")

      values.each do |value|
        # The icalendar gem stores parameters in ical_params
        # The field name is in the "name" parameter, and the value is the property value itself
        next unless value.respond_to?(:ical_params) && value.ical_params["name"].present?

        field_name = value.ical_params["name"].first
        field_value = value.to_s.strip
        fields[field_name] = field_value
      end
    end

    fields
  end

  def parse_ics_time(ics_time)
    return nil unless ics_time

    # Handle Icalendar::Values::Date (all-day events)
    if ics_time.is_a?(Icalendar::Values::Date) || (ics_time.respond_to?(:value) && ics_time.value.is_a?(Date) && !ics_time.value.is_a?(DateTime))
      date = ics_time.respond_to?(:value) ? ics_time.value : ics_time
      Time.zone.local(date.year, date.month, date.day, 0, 0, 0)
    elsif ics_time.respond_to?(:to_time)
      ics_time.to_time.in_time_zone(Time.zone)
    else
      Time.zone.parse(ics_time.to_s)
    end
  end

  def all_day_event?(ics_event)
    # Check if dtstart is a Date (not DateTime)
    dtstart = ics_event.dtstart
    return true if dtstart.is_a?(Icalendar::Values::Date)
    return true if dtstart.respond_to?(:value) && dtstart.value.is_a?(Date) && !dtstart.value.is_a?(DateTime)

    # Check Microsoft all-day property
    all_day_prop = ics_event.custom_properties["x_microsoft_cdo_alldayevent"]
    return true if all_day_prop&.first&.to_s&.upcase == "TRUE"

    false
  end

  def extract_recurrence(ics_event)
    return nil if ics_event.rrule.blank?

    ics_event.rrule.map(&:to_s)
  end

  def clean_description(description)
    return nil if description.blank?

    # Remove HTML tags and decode entities
    result = description
             .gsub(/<br\s*\/?>/, "\n")
             .gsub(/<[^>]+>/, "")

    decode_html_entities(result)&.strip&.presence
  end

  # Decode HTML entities using HTMLEntities gem for robust handling
  # Handles: &amp; -> &, &nbsp; -> space, &ndash; -> –, &#123; -> numeric entities, etc.
  def decode_html_entities(text)
    return nil if text.blank?

    html_entities_decoder.decode(text.to_s)
  end

  # Memoized HTMLEntities instance for performance when processing many events
  def html_entities_decoder
    @html_entities_decoder ||= HTMLEntities.new
  end

  def find_term_from_academic_term(academic_term_str, event_date)
    # Parse "Fall", "Spring", "Summer" and find matching term
    season = case academic_term_str.to_s.downcase
             when /fall/ then :fall
             when /spring/ then :spring
             when /summer/ then :summer
             end

    return nil unless season

    # Determine year from event date
    year = event_date.year
    # Fall semester events in early months might reference the previous fall term
    year -= 1 if season == :fall && event_date.month < 6

    Term.find_by(year: year, season: season)
  end

end
