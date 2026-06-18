# frozen_string_literal: true

class GoogleCalendarService
  include GoogleApiRateLimiter

  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def create_or_get_course_calendar
    google_calendar = GoogleCalendar.for_user(user).first
    newly_created   = false

    if google_calendar.blank?
      google_api_calendar = create_calendar_with_service_account
      primary_credential  = user.google_credential || user.google_credentials.first
      raise "No Google OAuth credentials found for user" unless primary_credential

      google_calendar = primary_credential.create_google_calendar!(
        google_calendar_id: google_api_calendar.id,
        summary:            google_api_calendar.summary,
        description:        google_api_calendar.description,
        time_zone:          google_api_calendar.time_zone
      )
      newly_created = true
    end

    calendar_id = google_calendar.google_calendar_id

    share_calendar_with_user(calendar_id)
    add_calendar_to_all_oauth_users(calendar_id)

    if newly_created && user.enrollments.any?
      GoogleCalendarSyncJob.perform_later(user, force: true)
    end

    calendar_id
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to create Google Calendar: #{e.message}"
    raise "Failed to create course calendar: #{e.message}"
  end

  def update_calendar_events(events, force: false)
    service         = user_calendar_service
    google_calendar = GoogleCalendar.for_user(user).first
    return { created: 0, updated: 0, skipped: 0 } unless google_calendar

    calendar_id = google_calendar.google_calendar_id

    all_existing_events = google_calendar.google_calendar_events.to_a
    existing_events     = {}
    duplicates_to_delete = []

    all_existing_events.each do |e|
      event_key = build_event_key(e)

      if existing_events[event_key]
        if e.created_at > existing_events[event_key].created_at
          duplicates_to_delete << existing_events[event_key]
          existing_events[event_key] = e
        else
          duplicates_to_delete << e
        end
      else
        existing_events[event_key] = e
      end
    end

    if duplicates_to_delete.any?
      Rails.logger.info "Cleaning up #{duplicates_to_delete.size} duplicate calendar events"
      with_batch_throttling(duplicates_to_delete) do |cal_event|
        delete_event_from_calendar(service, google_calendar, cal_event)
      end
    end

    current_event_keys = events.map { |e| build_event_key_from_hash(e) }.compact

    events_to_delete = existing_events.except(*current_event_keys).reject do |_key, cal_event|
      cal_event.end_time&.past?
    end
    with_batch_throttling(events_to_delete.values) do |cal_event|
      delete_event_from_calendar(service, google_calendar, cal_event)
    end

    stats              = { created: 0, updated: 0, skipped: 0 }
    preference_resolver = PreferenceResolver.new(user)
    template_renderer   = CalendarTemplateRenderer.new

    events.each do |event|
      event_key      = build_event_key_from_hash(event)
      existing_event = existing_events[event_key]

      if existing_event
        syncable             = resolve_syncable(event)
        event_with_prefs     = apply_preferences_to_event(syncable, event, preference_resolver: preference_resolver, template_renderer: template_renderer)

        if force || existing_event.data_changed?(event_with_prefs)
          result = update_event_in_calendar(service, google_calendar, existing_event, event_with_prefs, force: force, preference_resolver: preference_resolver, template_renderer: template_renderer)
          stats[:updated] += 1 if result == :updated
          stats[:skipped] += 1 if result == :skipped_user_edit
        else
          existing_event.mark_synced!
          stats[:skipped] += 1
        end
      else
        create_event_in_calendar(service, google_calendar, event, preference_resolver: preference_resolver, template_renderer: template_renderer)
        stats[:created] += 1
      end
    end

    total_processed  = stats[:created] + stats[:updated] + stats[:skipped]
    skip_percentage  = total_processed > 0 ? (stats[:skipped].to_f / total_processed * 100).round(2) : 0

    Rails.logger.info({
      message: "Calendar sync completed",
      user_id: user.id,
      events_created: stats[:created],
      events_updated: stats[:updated],
      events_skipped: stats[:skipped],
      total_processed: total_processed,
      skip_percentage: skip_percentage
    }.to_json)

    stats
  end

  def update_specific_events(events, force: false)
    service         = user_calendar_service
    google_calendar = GoogleCalendar.for_user(user).first

    unless google_calendar
      Rails.logger.warn({ message: "Cannot update events - no Google Calendar found", user_id: user&.id, event_count: events.size }.to_json)
      return { created: 0, updated: 0, skipped: 0 }
    end

    meeting_time_ids    = events.filter_map { |e| e[:meeting_time_id] }
    final_exam_ids      = events.filter_map { |e| e[:final_exam_id] }
    university_event_ids = events.filter_map { |e| e[:university_calendar_event_id] }

    base_query = google_calendar.google_calendar_events
    conditions = []
    conditions << base_query.where(meeting_time_id: meeting_time_ids)         if meeting_time_ids.any?
    conditions << base_query.where(final_exam_id: final_exam_ids)             if final_exam_ids.any?
    conditions << base_query.where(university_calendar_event_id: university_event_ids) if university_event_ids.any?

    query = conditions.reduce { |q, c| q.or(c) } || base_query

    existing_events = query.index_by { |e| build_event_key(e) }

    preference_resolver = PreferenceResolver.new(user)
    template_renderer   = CalendarTemplateRenderer.new
    stats = { created: 0, updated: 0, skipped: 0 }

    events.each do |event|
      event_key      = build_event_key_from_hash(event)
      existing_event = existing_events[event_key]

      if existing_event
        syncable         = resolve_syncable(event)
        event_with_prefs = apply_preferences_to_event(syncable, event, preference_resolver: preference_resolver, template_renderer: template_renderer)

        if force || existing_event.data_changed?(event_with_prefs)
          update_event_in_calendar(service, google_calendar, existing_event, event_with_prefs, force: force, preference_resolver: preference_resolver, template_renderer: template_renderer)
          stats[:updated] += 1
        else
          existing_event.mark_synced!
          stats[:skipped] += 1
        end
      else
        create_event_in_calendar(service, google_calendar, event, preference_resolver: preference_resolver, template_renderer: template_renderer)
        stats[:created] += 1
      end
    end

    Rails.logger.info "Partial sync complete: #{stats[:created]} created, #{stats[:updated]} updated, #{stats[:skipped]} skipped"
    stats
  end

  def list_calendars
    service = service_account_calendar_service
    with_rate_limit_handling { service.list_calendar_lists }
  end

  def delete_calendar(calendar_id)
    google_calendar = GoogleCalendar.find_by(google_calendar_id: calendar_id)

    if google_calendar
      calendar_user = google_calendar.user
      credentials   = calendar_user.google_credentials.to_a

      with_batch_throttling(credentials) do |credential|
        remove_calendar_from_user_list_for_email(calendar_id, credential.email)
      end
    end

    service = service_account_calendar_service
    with_rate_limit_handling { service.delete_calendar(calendar_id) }
  end

  private

  def build_event_key(e)
    if e.meeting_time_id
      "mt_#{e.meeting_time_id}"
    elsif e.final_exam_id
      "fe_#{e.final_exam_id}"
    else
      "ue_#{e.university_calendar_event_id}"
    end
  end

  def build_event_key_from_hash(e)
    if e[:meeting_time_id]
      "mt_#{e[:meeting_time_id]}"
    elsif e[:final_exam_id]
      "fe_#{e[:final_exam_id]}"
    elsif e[:university_calendar_event_id]
      "ue_#{e[:university_calendar_event_id]}"
    end
  end

  def resolve_syncable(event)
    if event[:meeting_time_id]
      Course::MeetingTime.includes(course: :faculties).find_by(id: event[:meeting_time_id])
    elsif event[:final_exam_id]
      FinalExam.includes(course: :faculties).find_by(id: event[:final_exam_id])
    elsif event[:university_calendar_event_id]
      UniversityCalendarEvent.find_by(id: event[:university_calendar_event_id])
    else
      raise "Unknown event type — missing meeting_time_id, final_exam_id, or university_calendar_event_id"
    end
  end

  def service_account_calendar_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = service_account_credentials
    service
  end

  def service_account_credentials
    service_account_config = Rails.application.credentials.dig(:google, :service_account)

    credentials_json = if service_account_config.is_a?(String)
                         service_account_config
    else
                         service_account_config.to_json
    end

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(credentials_json),
      scope:       Google::Apis::CalendarV3::AUTH_CALENDAR
    )
  end

  def user_calendar_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = user_google_authorization
    service
  end

  def user_google_authorization
    raise "User has no Google credential" unless user.google_credential
    raise "User has no Google access token" if user.google_access_token.blank?

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope:         [ "https://www.googleapis.com/auth/calendar" ],
      access_token:  user.google_access_token,
      refresh_token: user.google_refresh_token,
      expires_at:    user.google_token_expires_at
    )

    if user.google_credential.token_expired?
      credentials.refresh!
      user.google_credential.update!(
        access_token:      credentials.access_token,
        token_expires_at:  Time.zone.at(credentials.expires_at)
      )
      user.instance_variable_set(:@google_credential, nil)
    end

    credentials
  end

  def create_calendar_with_service_account
    service    = service_account_calendar_service
    env_prefix = { "test" => "[TEST] ", "development" => "[DEV] ", "stage" => "[STAGE] " }[Rails.env] || ""

    calendar = Google::Apis::CalendarV3::Calendar.new(
      summary:     "#{env_prefix}WIT Courses",
      description: "#{env_prefix}Course schedule for #{user.email}.\nCreated and Updated by WIT Course Calendar App.",
      time_zone:   "America/New_York"
    )

    with_rate_limit_handling { service.insert_calendar(calendar) }
  end

  # Share the calendar with all of the user's Google-authenticated emails via ACL.
  def share_calendar_with_user(calendar_id)
    service     = service_account_calendar_service
    credentials = user.google_credentials.to_a

    with_batch_throttling(credentials) do |credential|
      rule = Google::Apis::CalendarV3::AclRule.new(
        scope: { type: "user", value: credential.email },
        role:  "owner"
      )

      begin
        service.insert_acl(calendar_id, rule, send_notifications: false)
      rescue Google::Apis::ClientError => e
        raise unless e.status_code == 409
      end
    end
  end

  def add_calendar_to_all_oauth_users(calendar_id)
    credentials = user.google_credentials.to_a

    with_batch_throttling(credentials) do |credential|
      add_calendar_to_user_list_for_email(calendar_id, credential.email)
    end
  end

  def add_calendar_to_user_list_for_email(calendar_id, email)
    credential = user.google_credential_for_email(email)
    return unless credential

    service = user_calendar_service_for_credential(credential)

    calendar_list_entry = Google::Apis::CalendarV3::CalendarListEntry.new(
      id:               calendar_id,
      summary_override: "WIT Courses",
      color_id:         "7",
      selected:         true,
      hidden:           false
    )

    retries = 0
    max_retries = 3

    begin
      with_rate_limit_handling { service.insert_calendar_list(calendar_list_entry) }
    rescue Google::Apis::ClientError => e
      if e.status_code == 409
        Rails.logger.debug { "Calendar #{calendar_id} already in list for #{email}" }
      elsif e.status_code == 404 && retries < max_retries
        retries += 1
        wait_time = 10 * retries
        Rails.logger.warn "Calendar #{calendar_id} not accessible yet for #{email} - retrying in #{wait_time}s (attempt #{retries}/#{max_retries})"
        sleep(wait_time)
        retry
      elsif e.status_code == 404
        Rails.logger.error "Calendar #{calendar_id} still not accessible for #{email} after #{max_retries} retries"
        raise
      else
        raise
      end
    end
  end

  def remove_calendar_from_user_list_for_email(calendar_id, email)
    google_calendar = GoogleCalendar.find_by(google_calendar_id: calendar_id)
    return unless google_calendar

    calendar_user = google_calendar.user
    credential    = calendar_user.google_credential_for_email(email)
    return unless credential

    service = user_calendar_service_for_credential(credential)
    with_rate_limit_handling { service.delete_calendar_list(calendar_id) }
  rescue Google::Apis::ClientError => e
    Rails.logger.warn "Failed to remove calendar from user list: #{e.message}" unless e.status_code == 404
  end

  def user_calendar_service_for_credential(credential)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = user_google_authorization_for_credential(credential)
    service
  end

  def user_google_authorization_for_credential(credential)
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope:         [ "https://www.googleapis.com/auth/calendar" ],
      access_token:  credential.access_token,
      refresh_token: credential.refresh_token,
      expires_at:    credential.token_expires_at
    )

    if credential.token_expired?
      credentials.refresh!
      credential.update!(
        access_token:     credentials.access_token,
        token_expires_at: Time.zone.at(credentials.expires_at)
      )
    end

    credentials
  end

  def create_event_in_calendar(service, google_calendar, course_event, preference_resolver: nil, template_renderer: nil)
    calendar_id = google_calendar.google_calendar_id
    syncable    = resolve_syncable(course_event)
    event_data  = apply_preferences_to_event(syncable, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

    google_event = build_google_event(event_data)

    created_event = with_rate_limit_handling { service.insert_event(calendar_id, google_event) }

    event_attributes = {
      google_event_id:  created_event.id,
      summary:          event_data[:summary],
      location:         event_data[:location],
      start_time:       event_data[:start_time],
      end_time:         event_data[:end_time],
      recurrence:       event_data[:recurrence],
      event_data_hash:  GoogleCalendarEvent.generate_data_hash(event_data),
      last_synced_at:   Time.current
    }

    if course_event[:meeting_time_id]
      event_attributes[:meeting_time_id] = course_event[:meeting_time_id]
    elsif course_event[:final_exam_id]
      event_attributes[:final_exam_id] = course_event[:final_exam_id]
    elsif course_event[:university_calendar_event_id]
      event_attributes[:university_calendar_event_id] = course_event[:university_calendar_event_id]
    end

    google_calendar.google_calendar_events.create!(event_attributes)
  end

  def update_event_in_calendar(service, google_calendar, db_event, course_event, force: false, preference_resolver: nil, template_renderer: nil)
    unless force || db_event.data_changed?(course_event)
      db_event.mark_synced!
      return :skipped_no_change
    end

    calendar_id        = google_calendar.google_calendar_id
    current_gcal_event = nil
    newly_edited_fields = []

    unless force
      begin
        current_gcal_event = with_rate_limit_handling { service.get_event(calendar_id, db_event.google_event_id) }

        newly_edited_fields = detect_user_edited_fields(db_event, current_gcal_event)

        gcal_recurrence    = current_gcal_event.recurrence
        recurrence_changed = normalize_recurrence(gcal_recurrence) != normalize_recurrence(db_event.recurrence)

        if recurrence_changed
          Rails.logger.info "User edited recurrence in Google Calendar: #{db_event.google_event_id}. Preserving user changes."
          update_db_from_gcal_event(db_event, current_gcal_event)
          db_event.mark_synced!
          return :skipped_user_edit
        end
      rescue Google::Apis::ClientError => e
        raise unless e.status_code == 404

        Rails.logger.warn({ message: "Event not found in Google Calendar, recreating",
                            user_id: user.id, google_event_id: db_event.google_event_id }.to_json)
        db_event.destroy
        create_event_in_calendar(service, google_calendar, course_event)
        return :recreated
      end
    end

    syncable   = resolve_syncable(course_event)
    event_data = apply_preferences_to_event(syncable, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

    all_edited_fields = force ? [] : ((db_event.user_edited_fields || []) + newly_edited_fields).uniq

    merged_event_data = event_data.dup
    if all_edited_fields.any? && current_gcal_event
      all_edited_fields.each do |field|
        case field
        when "summary"      then merged_event_data[:summary]     = current_gcal_event.summary
        when "location"     then merged_event_data[:location]    = current_gcal_event.location
        when "description"  then merged_event_data[:description] = current_gcal_event.description
        when "start_time"   then merged_event_data[:start_time]  = parse_gcal_time(current_gcal_event.start)
        when "end_time"     then merged_event_data[:end_time]    = parse_gcal_time(current_gcal_event.end)
        end
      end
    end

    google_event = build_google_event(merged_event_data)
    with_rate_limit_handling { service.update_event(calendar_id, db_event.google_event_id, google_event) }

    db_event.update!(
      summary:           merged_event_data[:summary],
      location:          merged_event_data[:location],
      start_time:        merged_event_data[:start_time],
      end_time:          merged_event_data[:end_time],
      recurrence:        merged_event_data[:recurrence],
      event_data_hash:   GoogleCalendarEvent.generate_data_hash(merged_event_data),
      last_synced_at:    Time.current,
      user_edited_fields: all_edited_fields.any? ? all_edited_fields : nil
    )

    Rails.logger.info({ message: "Google Calendar event updated", user_id: user.id,
                        google_event_id: db_event.google_event_id, forced: force,
                        color_id: merged_event_data[:color_id], user_edited_fields: all_edited_fields }.to_json)

    :updated
  end

  def delete_event_from_calendar(service, google_calendar, db_event)
    calendar_id = google_calendar.google_calendar_id
    with_rate_limit_handling { service.delete_event(calendar_id, db_event.google_event_id) }
    db_event.destroy
  rescue Google::Apis::ClientError => e
    raise unless e.status_code == 404

    Rails.logger.warn({ message: "Event not found in Google Calendar, removing from database",
                        user_id: user.id, google_event_id: db_event.google_event_id }.to_json)
    db_event.destroy
  end

  def detect_user_edited_fields(db_event, gcal_event)
    edited_fields = []

    gcal_start_time = parse_gcal_time(gcal_event.start)
    gcal_end_time   = parse_gcal_time(gcal_event.end)

    edited_fields << "summary"     if gcal_event.summary   != db_event.summary
    edited_fields << "location"    if gcal_event.location  != db_event.location
    edited_fields << "description" if gcal_event.description.present?

    start_changed = if gcal_start_time.nil? || db_event.start_time.nil?
                      gcal_start_time != db_event.start_time
    else
                      gcal_start_time.to_i != db_event.start_time.to_i
    end
    edited_fields << "start_time" if start_changed

    end_changed = if gcal_end_time.nil? || db_event.end_time.nil?
                    gcal_end_time != db_event.end_time
    else
                    gcal_end_time.to_i != db_event.end_time.to_i
    end
    edited_fields << "end_time" if end_changed

    Rails.logger.info "User edit detected - Fields: #{edited_fields.join(', ')}" if edited_fields.any?
    edited_fields
  end

  def user_edited_event?(db_event, gcal_event)
    return true if detect_user_edited_fields(db_event, gcal_event).any?

    normalize_recurrence(gcal_event.recurrence) != normalize_recurrence(db_event.recurrence)
  end

  def update_db_from_gcal_event(db_event, gcal_event)
    summary    = gcal_event.summary
    location   = gcal_event.location
    start_time = parse_gcal_time(gcal_event.start)
    end_time   = parse_gcal_time(gcal_event.end)
    recurrence = gcal_event.recurrence

    event_data = { summary: summary, location: location, start_time: start_time, end_time: end_time, recurrence: recurrence }

    db_event.update!(
      summary:         summary,
      location:        location,
      start_time:      start_time,
      end_time:        end_time,
      recurrence:      recurrence,
      event_data_hash: GoogleCalendarEvent.generate_data_hash(event_data),
      last_synced_at:  Time.current
    )

    Rails.logger.info "Updated local DB with user's Google Calendar edits for event: #{db_event.google_event_id}"
  end

  def parse_gcal_time(time_obj)
    return nil unless time_obj

    if time_obj.date_time
      if time_obj.date_time.is_a?(String)
        Time.zone.parse(time_obj.date_time).in_time_zone("America/New_York")
      else
        time_obj.date_time.in_time_zone("America/New_York")
      end
    elsif time_obj.date
      if time_obj.date.is_a?(String)
        Time.zone.parse(time_obj.date).in_time_zone("America/New_York")
      else
        time_obj.date.in_time_zone("America/New_York")
      end
    end
  end

  def normalize_recurrence(recurrence)
    return nil if recurrence.blank?

    Array(recurrence).compact.sort
  end

  def apply_preferences_to_event(syncable, course_event, preference_resolver: nil, template_renderer: nil)
    return course_event unless syncable

    resolver = preference_resolver || PreferenceResolver.new(user)
    renderer = template_renderer  || CalendarTemplateRenderer.new

    prefs = resolver.resolve_for(syncable)

    context = case syncable
    when FinalExam
                CalendarTemplateRenderer.build_context_from_final_exam(syncable)
    when UniversityCalendarEvent
                CalendarTemplateRenderer.build_context_from_university_calendar_event(syncable)
    else
                CalendarTemplateRenderer.build_context_from_meeting_time(syncable)
    end

    event_data = course_event.dup

    event_data[:summary]     = renderer.render(prefs[:title_template], context)       if prefs[:title_template].present?
    event_data[:description] = renderer.render(prefs[:description_template], context) if prefs[:description_template].present?
    event_data[:location]    = renderer.render(prefs[:location_template], context)    if prefs[:location_template].present?

    event_data[:reminder_settings] = prefs[:reminder_settings] unless prefs[:reminder_settings].nil?
    event_data[:color_id]           = prefs[:color_id].present? ? normalize_color_id(prefs[:color_id]) : nil
    event_data[:visibility]         = prefs[:visibility] if prefs[:visibility].present?

    event_data
  end

  def normalize_color_id(color_id_or_hex)
    return nil if color_id_or_hex.blank?

    if color_id_or_hex.is_a?(Integer)
      return color_id_or_hex if (1..11).cover?(color_id_or_hex)
      return nil
    end

    if color_id_or_hex.is_a?(String) && color_id_or_hex.match?(/\A\d+\z/)
      id = color_id_or_hex.to_i
      return id if (1..11).cover?(id)
      return nil
    end

    if color_id_or_hex.is_a?(String) && color_id_or_hex.start_with?("#")
      normalized_hex  = color_id_or_hex.downcase
      witcc_color_id  = GoogleColors.witcc_to_color_id(normalized_hex)
      return witcc_color_id if witcc_color_id.present?

      GoogleColors::EVENT_MAP.each do |key, hex_value|
        return key if key.is_a?(Integer) && hex_value == normalized_hex
      end
    end

    nil
  end

  def convert_time_to_minutes(time, type)
    time_value = time.to_f

    case type
    when "hours" then (time_value * 60).to_i
    when "days"  then (time_value * 1440).to_i
    else time_value.to_i
    end
  end

  def build_google_event(event_data)
    google_event = Google::Apis::CalendarV3::Event.new(
      summary:     event_data[:summary],
      description: event_data[:description],
      location:    event_data[:location],
      color_id:    event_data[:color_id]&.to_s
    )

    if event_data[:all_day]
      google_event.start = { date: event_data[:start_time].to_date.to_s }
      google_event.end   = { date: (event_data[:end_time].to_date + 1.day).to_s }
    else
      start_time_et = event_data[:start_time].in_time_zone("America/New_York")
      end_time_et   = event_data[:end_time].in_time_zone("America/New_York")

      google_event.start = { date_time: start_time_et.iso8601, time_zone: "America/New_York" }
      google_event.end   = { date_time: end_time_et.iso8601,   time_zone: "America/New_York" }
    end

    google_event.recurrence = event_data[:recurrence] if event_data[:recurrence].present?

    if event_data[:reminder_settings].present? && event_data[:reminder_settings].is_a?(Array)
      valid_reminders = event_data[:reminder_settings].select do |reminder|
        reminder.is_a?(Hash) &&
          reminder["method"].present? &&
          reminder["time"].present? &&
          reminder["type"].present? &&
          [ "email", "popup", "notification" ].include?(reminder["method"])
      end

      if valid_reminders.any?
        google_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
          use_default: false,
          overrides:   valid_reminders.map do |reminder|
            method  = reminder["method"] == "notification" ? "popup" : reminder["method"]
            minutes = convert_time_to_minutes(reminder["time"], reminder["type"])
            Google::Apis::CalendarV3::EventReminder.new(reminder_method: method, minutes: minutes)
          end
        )
      end
    end

    google_event.visibility = event_data[:visibility] if event_data[:visibility].present?

    google_event
  end
end
