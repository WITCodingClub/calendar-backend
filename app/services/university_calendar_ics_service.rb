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
    stats = { created: 0, updated: 0, unchanged: 0, merged: 0, errors: [] }

    # First, extract attributes from all ICS events
    event_attrs_list = []
    ics_events.each do |ics_event|
      attrs = build_event_attributes(ics_event)
      event_attrs_list << attrs if attrs
    rescue => e
      stats[:errors] << "Error processing event #{ics_event.uid}: #{e.message}"
      Rails.logger.error("Failed to process ICS event: #{e.message}")
    end

    # Merge consecutive same-named events into multi-day events
    merged_events = merge_consecutive_events(event_attrs_list)
    stats[:merged] = event_attrs_list.size - merged_events.size if event_attrs_list.size > merged_events.size

    # Save each (possibly merged) event
    merged_events.each do |attrs|
      save_event(attrs, stats)
    rescue => e
      stats[:errors] << "Error saving event #{attrs[:ics_uid]}: #{e.message}"
      Rails.logger.error("Failed to save event: #{e.message}")
    end

    stats
  end

  # Build event attributes from an ICS event without saving
  # @param ics_event [Icalendar::Event] The ICS event to parse
  # @return [Hash, nil] Event attributes hash or nil if invalid
  def build_event_attributes(ics_event)
    return nil if ics_event.dtstart.nil?

    raw_custom_fields = extract_custom_fields(ics_event)
    organization = decode_html_entities(raw_custom_fields["Organization"])
    academic_term = decode_html_entities(raw_custom_fields["Academic Term"])
    event_type = decode_html_entities(raw_custom_fields["Event Type"])
    event_name = decode_html_entities(raw_custom_fields["Event Name"])

    summary = event_name.presence || decode_html_entities(ics_event.summary.to_s)
    location = decode_html_entities(ics_event.location&.to_s)
    start_time = parse_ics_time(ics_event.dtstart)
    end_time = parse_ics_time(ics_event.dtend || ics_event.dtstart)
    description = clean_description(ics_event.description&.to_s)
    category = UniversityCalendarEvent.infer_category(summary, event_type)
    is_all_day = category == "holiday" || all_day_event?(ics_event)

    if is_all_day
      original_end_date = end_time.to_date
      start_time = start_time.beginning_of_day
      end_time = original_end_date.end_of_day
    end

    {
      ics_uid: ics_event.uid.to_s,
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
      event_type_raw: event_type
    }
  end

  # Merge consecutive same-named events into multi-day events
  # Events are considered consecutive if they have the same summary, category,
  # and their dates are adjacent (within 1 day)
  # @param event_attrs_list [Array<Hash>] List of event attribute hashes
  # @return [Array<Hash>] List with consecutive events merged
  def merge_consecutive_events(event_attrs_list)
    return event_attrs_list if event_attrs_list.size <= 1

    # Group events by a merge key (summary + category + academic_term)
    # Only consider all-day events for merging
    grouped = event_attrs_list.group_by do |attrs|
      if attrs[:all_day]
        [attrs[:summary]&.downcase&.strip, attrs[:category], attrs[:academic_term]]
      else
        # Non-all-day events get unique keys so they don't merge
        [:no_merge, attrs[:ics_uid]]
      end
    end

    merged_results = []

    grouped.each do |key, events|
      if key.first == :no_merge || events.size == 1
        # Don't merge non-all-day events or single events
        merged_results.concat(events)
      else
        # Sort by start_time and try to merge consecutive events
        sorted = events.sort_by { |e| e[:start_time] }
        merged_results.concat(merge_consecutive_group(sorted))
      end
    end

    merged_results
  end

  # Merge a group of sorted events with the same summary into consecutive multi-day events
  # @param sorted_events [Array<Hash>] Events sorted by start_time
  # @return [Array<Hash>] Merged events
  def merge_consecutive_group(sorted_events)
    return sorted_events if sorted_events.empty?

    result = []
    current = sorted_events.first.dup
    current[:merged_uids] = [current[:ics_uid]]

    sorted_events[1..].each do |event|
      # Check if this event is consecutive with current (within 1 day)
      current_end_date = current[:end_time].to_date
      event_start_date = event[:start_time].to_date
      days_between = (event_start_date - current_end_date).to_i

      if days_between <= 1
        # Merge: extend current event's end_time and track merged UIDs
        current[:end_time] = event[:end_time]
        current[:merged_uids] << event[:ics_uid]
        # Keep description from first event, but could concatenate if different
        current[:description] ||= event[:description]
      else
        # Not consecutive, save current and start new
        result << finalize_merged_event(current)
        current = event.dup
        current[:merged_uids] = [current[:ics_uid]]
      end
    end

    # Don't forget the last event
    result << finalize_merged_event(current)
    result
  end

  # Finalize a merged event by setting the ics_uid appropriately
  # @param event [Hash] Event attributes with :merged_uids
  # @return [Hash] Event attributes with final :ics_uid
  def finalize_merged_event(event)
    merged_uids = event.delete(:merged_uids)
    if merged_uids.size > 1
      # Use a composite UID for merged events to track all source UIDs
      # Format: merged:<first_uid>+<count>
      event[:ics_uid] = "merged:#{merged_uids.first}+#{merged_uids.size}"
      Rails.logger.info("Merged #{merged_uids.size} events into multi-day event: #{event[:summary]} (#{event[:start_time].to_date} - #{event[:end_time].to_date})")
    end
    event
  end

  # Save or update an event in the database
  # @param attrs [Hash] Event attributes
  # @param stats [Hash] Stats hash to update
  def save_event(attrs, stats)
    # For merged events, also check for existing events with the first original UID
    # This handles the case where we previously imported single-day events
    ics_uid = attrs[:ics_uid]

    # Find existing event by ics_uid (handles both new merged UIDs and original single UIDs)
    event = UniversityCalendarEvent.find_or_initialize_by(ics_uid: ics_uid)

    # If this is a merged event and we didn't find it, check for old single-day events to clean up
    if event.new_record? && ics_uid.start_with?("merged:")
      # Extract the original first UID to migrate from
      original_uid = ics_uid.sub(/^merged:/, "").sub(/\+\d+$/, "")
      existing_single = UniversityCalendarEvent.find_by(ics_uid: original_uid)
      if existing_single
        # Update the existing single-day event to become the merged event
        event = existing_single
        # Clean up other single-day events that are now part of this merged event
        cleanup_merged_single_day_events(attrs, original_uid)
      end
    end

    # Check for content-based duplicates (same event with different UID)
    # This handles cases where the university feed has duplicate events
    if event.new_record?
      duplicate = find_duplicate_by_content(attrs)
      if duplicate
        Rails.logger.info("Skipping duplicate event: #{attrs[:summary]} (#{attrs[:ics_uid]}) - already exists as #{duplicate.ics_uid}")
        stats[:unchanged] += 1
        return
      end
    end

    was_new = event.new_record?

    event.assign_attributes(
      ics_uid: ics_uid,
      summary: attrs[:summary],
      description: attrs[:description],
      location: attrs[:location],
      start_time: attrs[:start_time],
      end_time: attrs[:end_time],
      all_day: attrs[:all_day],
      recurrence: attrs[:recurrence],
      category: attrs[:category],
      organization: attrs[:organization],
      academic_term: attrs[:academic_term],
      event_type_raw: attrs[:event_type_raw],
      last_fetched_at: Time.current,
      source_url: ics_url
    )

    # Link to term
    if attrs[:start_time]
      event.term = if event.academic_term.present?
                     find_term_from_academic_term(event.academic_term, attrs[:start_time], attrs[:category], attrs[:summary])
                   end
      event.term ||= Term.find_by_date(attrs[:start_time])
    end

    content_changed = event.changed? && (event.changed - ["last_fetched_at"]).any?

    if was_new || content_changed
      event.save!
      was_new ? stats[:created] += 1 : stats[:updated] += 1
    else
      event.update_column(:last_fetched_at, Time.current) if event.persisted? # rubocop:disable Rails/SkipsModelValidations
      stats[:unchanged] += 1
    end
  end

  # Find an existing event with matching content (but different UID)
  # This detects duplicates in the university feed where the same event appears multiple times
  # @param attrs [Hash] Event attributes to check
  # @return [UniversityCalendarEvent, nil] Existing duplicate event or nil
  def find_duplicate_by_content(attrs)
    # Look for events with the same summary, start_time, end_time, and category
    # This catches duplicates in the feed that have different UIDs
    UniversityCalendarEvent.where(
      summary: attrs[:summary],
      start_time: attrs[:start_time],
      end_time: attrs[:end_time],
      category: attrs[:category]
    ).where.not(ics_uid: attrs[:ics_uid]).first
  end

  # Clean up single-day events that have been merged into a multi-day event
  # Looks for events with the same summary within the merged date range
  # @param merged_attrs [Hash] The merged event attributes
  # @param excluded_uid [String] The UID to exclude (already being updated)
  def cleanup_merged_single_day_events(merged_attrs, excluded_uid)
    start_date = merged_attrs[:start_time].to_date
    end_date = merged_attrs[:end_time].to_date

    # Find other single-day events with same summary in the date range
    UniversityCalendarEvent.where(summary: merged_attrs[:summary])
                           .where.not(ics_uid: excluded_uid)
                           .where(start_time: start_date.beginning_of_day..end_date.end_of_day)
                           .where(category: merged_attrs[:category])
                           .find_each do |old_event|
                             Rails.logger.info("Removing single-day event merged into multi-day: #{old_event.ics_uid}")
                             old_event.destroy
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

    # Check for pseudo all-day pattern: 12:01pm - 11:59pm
    # This is how some university calendar systems represent all-day events
    start_time = parse_ics_time(ics_event.dtstart)
    end_time = parse_ics_time(ics_event.dtend)
    return true if pseudo_all_day_times?(start_time, end_time)

    false
  end

  # Detects events that span 12:01pm to 11:59pm which are effectively all-day
  # Some university calendar systems use this pattern instead of true all-day events
  def pseudo_all_day_times?(start_time, end_time)
    return false unless start_time && end_time

    # Check for 12:01 PM start (allowing some flexibility: 12:00-12:01)
    start_is_noon = start_time.hour == 12 && start_time.min <= 1

    # Check for 11:59 PM end (allowing flexibility: 11:58-11:59)
    end_is_midnight = end_time.hour == 23 && end_time.min >= 58

    start_is_noon && end_is_midnight
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

  def find_term_from_academic_term(academic_term_str, event_date, category = nil, summary = nil)
    # For term boundary events (classes begin/end), infer term from date rather than
    # blindly trusting the academic_term field, which may be incorrect in the source ICS feed
    if category == "term_dates"
      return infer_term_from_date_for_boundary_event(academic_term_str, event_date, summary)
    end

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

  # Infer the correct term for term boundary events (Classes Begin/End) based on date
  # This prevents misclassification when the ICS feed has incorrect academic_term labels
  # @param academic_term_str [String] The academic term string from ICS (may be incorrect)
  # @param event_date [Time] The event date
  # @param summary [String] The event summary for logging
  # @return [Term, nil] The correct term based on date inference
  def infer_term_from_date_for_boundary_event(academic_term_str, event_date, summary)
    # Infer season from the event date using typical academic calendar patterns
    inferred_season = case event_date.month
                      when 1..5 then :spring    # Jan-May: Spring semester
                      when 6..7 then :summer    # Jun-Jul: Summer semester
                      when 8..12 then :fall     # Aug-Dec: Fall semester
                      end

    year = event_date.year

    # Parse the claimed season from academic_term_str for validation
    claimed_season = case academic_term_str.to_s.downcase
                     when /fall/ then :fall
                     when /spring/ then :spring
                     when /summer/ then :summer
                     end

    # Log a warning if the claimed season doesn't match the date-inferred season
    if claimed_season && claimed_season != inferred_season
      Rails.logger.warn(
        "Term mismatch detected for '#{summary}': " \
        "ICS claims '#{academic_term_str}' but date #{event_date.to_date} suggests #{inferred_season.to_s.capitalize} #{year}. " \
        "Using date-based inference."
      )
    end

    # Use date-inferred season
    Term.find_by(year: year, season: inferred_season)
  end

end
