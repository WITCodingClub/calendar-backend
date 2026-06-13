# frozen_string_literal: true

class UniversityCalendarIcsService < ApplicationService
  ICS_FEED_URL = "https://25livepub.collegenet.com/calendars/wit-main-events-calendar.ics"

  def self.backfill_url(start_date, end_date)
    "#{ICS_FEED_URL}?startdt=#{start_date.to_date}&enddt=#{end_date.to_date}"
  end

  attr_reader :ics_url

  def initialize(ics_url: ICS_FEED_URL)
    @ics_url = ics_url
    all_terms = Term.all.to_a
    @term_cache = all_terms.index_by do |term|
      [term.year, term.season.to_sym]
    end
    @terms_with_dates = all_terms.select { |t| t.start_date && t.end_date }
    @term_by_date_cache = {}
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

    calendars.first.events
  end

  def process_events(ics_events)
    stats = { created: 0, updated: 0, unchanged: 0, merged: 0, cancelled: 0, errors: [], changed_categories: Set.new }

    event_attrs_list = []
    cancelled_uids   = []

    ics_events.each do |ics_event|
      if ics_event.status&.to_s&.upcase == "CANCELLED"
        cancelled_uids << ics_event.uid.to_s
        next
      end

      attrs = build_event_attributes(ics_event)
      event_attrs_list << attrs if attrs
    rescue => e
      stats[:errors] << "Error processing event #{ics_event.uid}: #{e.message}"
      Rails.logger.error("Failed to process ICS event: #{e.message}")
    end

    preload_existing_events

    cancel_events(cancelled_uids, stats)

    merged_events = merge_consecutive_events(event_attrs_list)
    stats[:merged] = event_attrs_list.size - merged_events.size if event_attrs_list.size > merged_events.size

    merged_events.each do |attrs|
      save_event(attrs, stats)
    rescue => e
      stats[:errors] << "Error saving event #{attrs[:ics_uid]}: #{e.message}"
      Rails.logger.error("Failed to save event: #{e.message}")
    end

    stats[:changed_categories] = stats[:changed_categories].to_a
    stats
  end

  def preload_existing_events
    all_events = UniversityCalendarEvent.all.to_a
    @existing_events_by_uid = all_events.index_by(&:ics_uid)
    @existing_events_by_content = all_events.group_by do |e|
      [e.summary, e.start_time, e.end_time, e.category]
    end
  end

  def cancel_events(uids, stats)
    return if uids.empty?

    uids.each do |uid|
      event = @existing_events_by_uid&.[](uid)
      next unless event

      Rails.logger.info("Removing CANCELLED ICS event: #{event.summary} (#{uid})")
      stats[:changed_categories] << event.category if event.category.present?
      event.destroy
      @existing_events_by_uid.delete(uid)
      stats[:cancelled] += 1
    end
  end

  def build_event_attributes(ics_event)
    return nil if ics_event.dtstart.nil?

    raw_custom_fields = extract_custom_fields(ics_event)
    organization  = decode_html_entities(raw_custom_fields["Organization"])
    academic_term = decode_html_entities(raw_custom_fields["Academic Term"])
    event_type    = decode_html_entities(raw_custom_fields["Event Type"])
    event_name    = decode_html_entities(raw_custom_fields["Event Name"])

    summary     = event_name.presence || decode_html_entities(ics_event.summary.to_s)
    location    = decode_html_entities(ics_event.location&.to_s)
    start_time  = parse_ics_time(ics_event.dtstart)
    end_time    = parse_ics_time(ics_event.dtend || ics_event.dtstart)
    description = clean_description(ics_event.description&.to_s)
    category    = UniversityCalendarEvent.infer_category(summary, event_type)
    is_all_day  = %w[holiday study_day].include?(category) || all_day_event?(ics_event)

    if is_all_day
      original_end_date = end_time.to_date
      start_time = start_time.beginning_of_day
      end_time   = original_end_date.end_of_day
    end

    {
      ics_uid:        ics_event.uid.to_s,
      summary:        summary,
      description:    description,
      location:       location,
      start_time:     start_time,
      end_time:       end_time,
      all_day:        is_all_day,
      recurrence:     extract_recurrence(ics_event),
      category:       category,
      organization:   organization,
      academic_term:  academic_term,
      event_type_raw: event_type
    }
  end

  def merge_consecutive_events(event_attrs_list)
    return event_attrs_list if event_attrs_list.size <= 1

    grouped = event_attrs_list.group_by do |attrs|
      if attrs[:all_day]
        [attrs[:summary]&.downcase&.strip, attrs[:category], attrs[:academic_term]]
      else
        [:no_merge, attrs[:ics_uid]]
      end
    end

    merged_results = []

    grouped.each do |key, events|
      if key.first == :no_merge || events.size == 1
        merged_results.concat(events)
      else
        sorted = events.sort_by { |e| e[:start_time] }
        merged_results.concat(merge_consecutive_group(sorted))
      end
    end

    merged_results
  end

  def merge_consecutive_group(sorted_events)
    return sorted_events if sorted_events.empty?

    result  = []
    current = sorted_events.first.dup
    current[:merged_uids] = [current[:ics_uid]]

    sorted_events[1..].each do |event|
      current_end_date  = current[:end_time].to_date
      event_start_date  = event[:start_time].to_date
      days_between      = (event_start_date - current_end_date).to_i

      if days_between <= 1
        current[:end_time] = event[:end_time]
        current[:merged_uids] << event[:ics_uid]
        current[:description] ||= event[:description]
      else
        result << finalize_merged_event(current)
        current = event.dup
        current[:merged_uids] = [current[:ics_uid]]
      end
    end

    result << finalize_merged_event(current)
    result
  end

  def finalize_merged_event(event)
    merged_uids = event.delete(:merged_uids)
    if merged_uids.size > 1
      event[:ics_uid] = "merged:#{merged_uids.first}+#{merged_uids.size}"
      Rails.logger.info("Merged #{merged_uids.size} events into multi-day event: #{event[:summary]} (#{event[:start_time].to_date} - #{event[:end_time].to_date})")
    end
    event
  end

  def save_event(attrs, stats)
    ics_uid = attrs[:ics_uid]
    event   = @existing_events_by_uid&.[](ics_uid) || UniversityCalendarEvent.new(ics_uid: ics_uid)

    if event.new_record? && ics_uid.start_with?("merged:")
      original_uid    = ics_uid.sub(/^merged:/, "").sub(/\+\d+$/, "")
      existing_single = @existing_events_by_uid&.[](original_uid)
      if existing_single
        event = existing_single
        cleanup_merged_single_day_events(attrs, original_uid)
      end
    end

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
      ics_uid:        ics_uid,
      summary:        attrs[:summary],
      description:    attrs[:description],
      location:       attrs[:location],
      start_time:     attrs[:start_time],
      end_time:       attrs[:end_time],
      all_day:        attrs[:all_day],
      recurrence:     attrs[:recurrence],
      category:       attrs[:category],
      organization:   attrs[:organization],
      academic_term:  attrs[:academic_term],
      event_type_raw: attrs[:event_type_raw],
      last_fetched_at: Time.current,
      source_url:     ics_url
    )

    if attrs[:start_time]
      event.term = if event.academic_term.present?
                     find_term_from_academic_term(event.academic_term, attrs[:start_time], attrs[:category], attrs[:summary])
                   end
      event.term ||= find_term_by_date_cached(attrs[:start_time])
    end

    if event.term && event.academic_term.present? && attrs[:category] == "term_dates"
      ics_season = case event.academic_term.downcase
                   when /fall/   then :fall
                   when /spring/ then :spring
                   when /summer/ then :summer
                   end

      if ics_season && ics_season != event.term.season
        event.summary = fix_summary_term_reference(event.summary, event.academic_term, event.term)
      end
    end

    content_changed = event.changed? && (event.changed - ["last_fetched_at"]).any?

    if was_new || content_changed
      event.save!
      stats[:changed_categories] << event.category if event.category.present?
      was_new ? stats[:created] += 1 : stats[:updated] += 1
      add_event_to_content_cache(event)
    else
      event.update_column(:last_fetched_at, Time.current) if event.persisted? # rubocop:disable Rails/SkipsModelValidations
      stats[:unchanged] += 1
    end
  end

  def find_duplicate_by_content(attrs)
    content_key = [attrs[:summary], attrs[:start_time], attrs[:end_time], attrs[:category]]

    if @existing_events_by_content
      candidates = (@existing_events_by_content[content_key] || []).reject { |e| e.ics_uid == attrs[:ics_uid] }
      return candidates.first if candidates.any?
    else
      exact_match = UniversityCalendarEvent.where(
        summary:    attrs[:summary],
        start_time: attrs[:start_time],
        end_time:   attrs[:end_time],
        category:   attrs[:category]
      ).where.not(ics_uid: attrs[:ics_uid]).first
      return exact_match if exact_match
    end

    fuzzy_matches = if @existing_events_by_content
                      find_fuzzy_duplicates_in_memory(attrs)
                    else
                      UniversityCalendarEvent.find_fuzzy_duplicates(
                        summary:     attrs[:summary],
                        start_time:  attrs[:start_time],
                        end_time:    attrs[:end_time],
                        category:    attrs[:category],
                        exclude_uid: attrs[:ics_uid]
                      )
                    end

    return nil if fuzzy_matches.empty?

    UniversityCalendarEvent.preferred_event(fuzzy_matches)
  end

  def add_event_to_content_cache(event)
    return unless @existing_events_by_content

    content_key = [event.summary, event.start_time, event.end_time, event.category]
    @existing_events_by_content[content_key] ||= []
    @existing_events_by_content[content_key] << event
    @existing_events_by_uid[event.ics_uid] = event if @existing_events_by_uid
  end

  def find_fuzzy_duplicates_in_memory(attrs)
    start_date      = attrs[:start_time].to_date
    end_date        = attrs[:end_time].to_date
    start_day_begin = start_date.beginning_of_day
    start_day_end   = start_date.end_of_day + 1.second
    end_day_begin   = end_date.beginning_of_day
    end_day_end     = end_date.end_of_day + 1.second

    all_events = @existing_events_by_content.values.flatten
    candidates = all_events.select do |e|
      e.category  == attrs[:category] &&
        e.ics_uid != attrs[:ics_uid] &&
        e.start_time >= start_day_begin && e.start_time < start_day_end &&
        e.end_time   >= end_day_begin   && e.end_time   < end_day_end
    end

    candidates.select do |event|
      UniversityCalendarEvent.similarity(attrs[:summary], event.summary) >= UniversityCalendarEvent::SIMILARITY_THRESHOLD
    end
  end

  def cleanup_merged_single_day_events(merged_attrs, excluded_uid)
    start_date = merged_attrs[:start_time].to_date
    end_date   = merged_attrs[:end_time].to_date

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

    ics_event.custom_properties.each do |key, values|
      next unless key.to_s.start_with?("x_trumba_customfield")

      values.each do |value|
        next unless value.respond_to?(:ical_params) && value.ical_params["name"].present?

        field_name  = value.ical_params["name"].first
        field_value = value.to_s.strip
        fields[field_name] = field_value
      end
    end

    fields
  end

  def parse_ics_time(ics_time)
    return nil unless ics_time

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
    dtstart = ics_event.dtstart
    return true if dtstart.is_a?(Icalendar::Values::Date)
    return true if dtstart.respond_to?(:value) && dtstart.value.is_a?(Date) && !dtstart.value.is_a?(DateTime)

    all_day_prop = ics_event.custom_properties["x_microsoft_cdo_alldayevent"]
    return true if all_day_prop&.first&.to_s&.upcase == "TRUE"

    start_time = parse_ics_time(ics_event.dtstart)
    end_time   = parse_ics_time(ics_event.dtend)
    return true if pseudo_all_day_times?(start_time, end_time)

    false
  end

  def pseudo_all_day_times?(start_time, end_time)
    return false unless start_time && end_time

    start_is_noon   = start_time.hour == 12 && start_time.min <= 1
    end_is_midnight = end_time.hour == 23 && end_time.min >= 58

    start_is_noon && end_is_midnight
  end

  def extract_recurrence(ics_event)
    return nil if ics_event.rrule.blank?

    ics_event.rrule.map(&:to_s)
  end

  def clean_description(description)
    return nil if description.blank?

    result = description
             .gsub(/<br\s*\/?>/, "\n")
             .gsub(/<[^>]+>/, "")

    decode_html_entities(result)&.strip&.presence
  end

  def decode_html_entities(text)
    return nil if text.blank?

    html_entities_decoder.decode(text.to_s)
  end

  def html_entities_decoder
    @html_entities_decoder ||= HTMLEntities.new
  end

  def find_term_from_academic_term(academic_term_str, event_date, category = nil, summary = nil)
    if category == "term_dates"
      return infer_term_from_date_for_boundary_event(academic_term_str, event_date, summary)
    end

    season = case academic_term_str.to_s.downcase
             when /fall/   then :fall
             when /spring/ then :spring
             when /summer/ then :summer
             end

    return nil unless season

    year = event_date.year
    year -= 1 if season == :fall && event_date.month < 6

    @term_cache[[year, season]]
  end

  def find_term_by_date_cached(date)
    date_key = date.to_date
    @term_by_date_cache[date_key] ||= @terms_with_dates.find { |t| date_key.between?(t.start_date, t.end_date) }
  end

  def infer_term_from_date_for_boundary_event(academic_term_str, event_date, summary)
    inferred_season = case event_date.month
                      when 1..5  then :spring
                      when 6..7  then :summer
                      when 8..12 then :fall
                      end

    year = event_date.year

    claimed_season = case academic_term_str.to_s.downcase
                     when /fall/   then :fall
                     when /spring/ then :spring
                     when /summer/ then :summer
                     end

    if claimed_season && claimed_season != inferred_season
      Rails.logger.warn(
        "Term mismatch detected for '#{summary}': " \
        "ICS claims '#{academic_term_str}' but date #{event_date.to_date} suggests #{inferred_season.to_s.capitalize} #{year}. " \
        "Using date-based inference."
      )
    end

    @term_cache[[year, inferred_season]]
  end

  def fix_summary_term_reference(summary, incorrect_term, correct_term)
    return summary if incorrect_term.blank? || correct_term.nil?

    year_match       = incorrect_term.match(/\d{4}/)
    correct_term_str = "#{correct_term.season.to_s.capitalize} #{correct_term.year}"

    corrected = summary.dup
    corrected = corrected.gsub(/for\s+(Fall|Spring|Summer)\s+\d{4}/i) { "for #{correct_term_str}" }

    if year_match
      corrected = corrected.gsub(/(Fall|Spring|Summer)\s+#{year_match[0]}/i, correct_term_str)
    end

    Rails.logger.info("Corrected summary: '#{summary}' -> '#{corrected}'") if corrected != summary

    corrected
  end
end
