# frozen_string_literal: true

class GoogleCalendarService
  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def create_or_get_course_calendar
    # Get or create the GoogleCalendar database record
    google_calendar = user.google_credential&.google_calendar

    # Create calendar if it doesn't exist
    if google_calendar.blank?
      google_api_calendar = create_calendar_with_service_account
      google_calendar = user.google_credential.create_google_calendar!(
        google_calendar_id: google_api_calendar.id,
        summary: google_api_calendar.summary,
        description: google_api_calendar.description,
        time_zone: google_api_calendar.time_zone
      )
    end

    calendar_id = google_calendar.google_calendar_id

    # Share calendar with all g_cal emails
    share_calendar_with_user(calendar_id)

    # Add calendar to each OAuth'd email's Google Calendar list
    add_calendar_to_all_oauth_users(calendar_id)

    calendar_id
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to create Google Calendar: #{e.message}"
    raise "Failed to create course calendar: #{e.message}"
  end

  def update_calendar_events(events, force: false)
    service = service_account_calendar_service
    google_calendar = user.google_credential&.google_calendar
    return { created: 0, updated: 0, skipped: 0 } unless google_calendar

    calendar_id = google_calendar.google_calendar_id

    # Get existing calendar events from database
    existing_events = google_calendar.google_calendar_events.index_by(&:meeting_time_id)

    # Track which meeting times are in the new events list
    current_meeting_time_ids = events.pluck(:meeting_time_id).compact

    # Delete events that are no longer needed
    events_to_delete = existing_events.except(*current_meeting_time_ids)
    events_to_delete.each_value do |cal_event|
      delete_event_from_calendar(service, google_calendar, cal_event)
    end

    # Stats for logging
    stats = { created: 0, updated: 0, skipped: 0 }

    # Initialize shared preference resolver and template renderer to avoid re-creating per event
    preference_resolver = PreferenceResolver.new(user)
    template_renderer = CalendarTemplateRenderer.new

    # Create or update events
    events.each do |event|
      meeting_time_id = event[:meeting_time_id]
      existing_event = existing_events[meeting_time_id]

      if existing_event
        # Update existing event if needed (or skip if no changes and not forced)
        if force || existing_event.data_changed?(event)
          update_event_in_calendar(service, google_calendar, existing_event, event, force: force, preference_resolver: preference_resolver, template_renderer: template_renderer)
          stats[:updated] += 1
        else
          existing_event.mark_synced!
          stats[:skipped] += 1
        end
      else
        # Create new event
        create_event_in_calendar(service, google_calendar, event, preference_resolver: preference_resolver, template_renderer: template_renderer)
        stats[:created] += 1
      end
    end

    Rails.logger.info "Sync complete: #{stats[:created]} created, #{stats[:updated]} updated, #{stats[:skipped]} skipped"
    stats
  end

  # Update only specific events (for partial syncs)
  def update_specific_events(events, force: false)
    service = service_account_calendar_service
    google_calendar = user.google_credential&.google_calendar
    return { created: 0, updated: 0, skipped: 0 } unless google_calendar

    # Preload existing events to avoid N+1 queries
    meeting_time_ids = events.map { |e| e[:meeting_time_id] }.compact
    existing_events = google_calendar.google_calendar_events
                                     .where(meeting_time_id: meeting_time_ids)
                                     .index_by(&:meeting_time_id)

    # Initialize shared preference resolver and template renderer to avoid re-creating per event
    preference_resolver = PreferenceResolver.new(user)
    template_renderer = CalendarTemplateRenderer.new

    stats = { created: 0, updated: 0, skipped: 0 }

    events.each do |event|
      meeting_time_id = event[:meeting_time_id]
      existing_event = existing_events[meeting_time_id]

      if existing_event
        if force || existing_event.data_changed?(event)
          update_event_in_calendar(service, google_calendar, existing_event, event, force: force, preference_resolver: preference_resolver, template_renderer: template_renderer)
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
    service.list_calendar_lists
  end

  def delete_calendar(calendar_id)
    # First, get the calendar to access its user
    google_calendar = GoogleCalendar.find_by(google_calendar_id: calendar_id)

    if google_calendar
      # Remove calendar from all OAuth'd users' calendar lists (sidebar)
      calendar_user = google_calendar.user
      calendar_user.google_credentials.find_each do |credential|
        remove_calendar_from_user_list_for_email(calendar_id, credential.email)
      end
    end

    # Then delete the actual calendar
    service = service_account_calendar_service
    service.delete_calendar(calendar_id)
  end

  def get_available_colors
    service = service_account_calendar_service
    service.get_color


  end

  private

  def service_account_calendar_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = service_account_credentials
    service
  end

  def service_account_credentials
    # Use IAM service account JSON key for all calendar operations
    # The service account credentials can be stored as a raw JSON string or as a
    # structured hash in Rails credentials. This method handles both cases.
    service_account_config = Rails.application.credentials.dig(:google, :service_account)

    credentials_json = if service_account_config.is_a?(String)
                         service_account_config
                       else
                         service_account_config.to_json
                       end

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(credentials_json),
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR
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
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: user.google_access_token,
      refresh_token: user.google_refresh_token,
      expires_at: user.google_token_expires_at
    )

    # Refresh the token if needed
    if user.google_credential.token_expired?
      credentials.refresh!
      user.google_credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.zone.at(credentials.expires_at)
      )
      # Clear the cached credential
      user.instance_variable_set(:@google_credential, nil)
    end

    credentials
  end

  def create_calendar_with_service_account
    service = service_account_calendar_service

    env_prefix = {
      "test"        => "[TEST] ",
      "development" => "[DEV] ",
      "stage"       => "[STAGE] "
    }[Rails.env] || ""

    calendar = Google::Apis::CalendarV3::Calendar.new(
      summary: "#{env_prefix}WIT Courses",
      description: "#{env_prefix}Course schedule for #{user.email}.\nCreated and Updated by WIT Course Calendar App.",
      time_zone: "America/New_York"
    )

    service.insert_calendar(calendar)
  end

  def share_calendar_with_user(calendar_id)
    service = service_account_calendar_service

    # for each user email where g_cal is true, share the calendar
    user.emails.where(g_cal: true).find_each do |email_record|
      rule = Google::Apis::CalendarV3::AclRule.new(
        scope: {
          type: "user",
          value: email_record.email
        },
        role: "writer" # writer access (can edit events)
      )

      service.insert_acl(
        calendar_id,
        rule,
        send_notifications: false # Don't send the default invite
      )
    rescue Google::Apis::ClientError => e
      # Ignore if user already has access
      raise unless e.status_code == 409
    end
  end

  def share_calendar_with_email(calendar_id, email_id)
    service = service_account_calendar_service
    email = Email.find_by(email: email_id, user_id: user.id)
    return unless email&.g_cal

    rule = Google::Apis::CalendarV3::AclRule.new(
      scope: {
        type: "user",
        value: email.email
      },
      # role: "reader" # reader access
      role: "writer" # writer access (can edit events)
    )

    service.insert_acl(
      calendar_id,
      rule,
      send_notifications: false
    )
  rescue Google::Apis::ClientError => e
    # Ignore if user already has access
    raise unless e.status_code == 409

  end

  def unshare_calendar_with_email(calendar_id, email_id)
    service = service_account_calendar_service
    email = Email.find_by(email: email_id, user_id: user.id)
    return unless email&.g_cal

    # Find the ACL entry for the email
    acl_list = service.list_acls(calendar_id)
    acl_entry = acl_list.items.find { |item| item.scope.type == "user" && item.scope.value == email.email }
    return unless acl_entry

    service.delete_acl(calendar_id, acl_entry.id)
  rescue Google::Apis::ClientError => e
    # Ignore if user doesn't have access
    raise unless e.status_code == 404
  end

  def add_calendar_to_all_oauth_users(calendar_id)
    # Add calendar to each OAuth'd email's Google Calendar list
    user.google_credentials.find_each do |credential|
      add_calendar_to_user_list_for_email(calendar_id, credential.email)
    end
  end

  def add_calendar_to_user_list_for_email(calendar_id, email)
    credential = user.google_credential_for_email(email)
    return unless credential

    service = user_calendar_service_for_credential(credential)

    calendar_list_entry = Google::Apis::CalendarV3::CalendarListEntry.new(
      id: calendar_id,
      summary_override: "WIT Courses",
      color_id: "5",
      selected: true,
      hidden: false
    )

    retries = 0
    max_retries = 3

    begin
      service.insert_calendar_list(calendar_list_entry)
    rescue Google::Apis::ClientError => e
      if e.status_code == 409
        # Calendar already in list - this is fine
        Rails.logger.debug { "Calendar #{calendar_id} already in list for #{email}" }
      elsif e.status_code == 404 && retries < max_retries
        # ACL hasn't propagated yet - retry with exponential backoff
        retries += 1
        wait_time = 10 * retries # 10s, 20s, 30s
        Rails.logger.warn "Calendar #{calendar_id} not accessible yet for #{email} - retrying in #{wait_time}s (attempt #{retries}/#{max_retries})"
        sleep(wait_time)
        retry
      elsif e.status_code == 404
        # Exhausted retries - ACL still hasn't propagated
        Rails.logger.error "Calendar #{calendar_id} still not accessible for #{email} after #{max_retries} retries - ACL may have failed to propagate"
        raise
      else
        raise
      end
    end
  end

  def remove_calendar_from_user_list_for_email(calendar_id, email)
    # Need to get the user from the calendar to access their credentials
    google_calendar = GoogleCalendar.find_by(google_calendar_id: calendar_id)
    return unless google_calendar

    calendar_user = google_calendar.user
    credential = calendar_user.google_credential_for_email(email)
    return unless credential

    service = user_calendar_service_for_credential(credential)
    service.delete_calendar_list(calendar_id)
  rescue Google::Apis::ClientError => e
    # Ignore if not in list (404) or already removed
    Rails.logger.warn "Failed to remove calendar from user list: #{e.message}" unless e.status_code == 404
  end

  def user_calendar_service_for_credential(credential)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = user_google_authorization_for_credential(credential)
    service
  end

  def user_google_authorization_for_credential(credential)
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: credential.access_token,
      refresh_token: credential.refresh_token,
      expires_at: credential.token_expires_at
    )

    # Refresh the token if needed
    if credential.token_expired?
      credentials.refresh!
      credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.zone.at(credentials.expires_at)
      )
    end

    credentials
  end

  def clear_calendar_events(service, calendar_id)
    # Get all events
    events = service.list_events(calendar_id)

    # Delete each event
    events.items.each do |event|
      service.delete_event(calendar_id, event.id)
    rescue Google::Apis::ClientError => e
      Rails.logger.warn "Failed to delete event: #{e.message}"
    end
  end

  def create_event_in_calendar(service, google_calendar, course_event, preference_resolver: nil, template_renderer: nil)
    calendar_id = google_calendar.google_calendar_id
    meeting_time = MeetingTime.includes(course: :faculties).find_by(id: course_event[:meeting_time_id])

    # Apply user preferences to event data
    event_data = apply_preferences_to_event(meeting_time, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

    # Ensure times are in Eastern timezone
    start_time_et = event_data[:start_time].in_time_zone("America/New_York")
    end_time_et = event_data[:end_time].in_time_zone("America/New_York")

    google_event = Google::Apis::CalendarV3::Event.new(
      summary: event_data[:summary],
      description: event_data[:description],
      location: event_data[:location],
      start: {
        date_time: start_time_et.iso8601,
        time_zone: "America/New_York"
      },
      end: {
        date_time: end_time_et.iso8601,
        time_zone: "America/New_York"
      },
      color_id: event_data[:color_id]&.to_s,
      recurrence: event_data[:recurrence]
    )

    # Apply reminders if present and valid
    if event_data[:reminder_settings].present? && event_data[:reminder_settings].is_a?(Array)
      # Filter to only valid reminders with required fields
      # Accept "notification" as alias for "popup"
      valid_reminders = event_data[:reminder_settings].select do |reminder|
        reminder.is_a?(Hash) &&
          reminder["method"].present? &&
          reminder["time"].present? &&
          reminder["type"].present? &&
          ["email", "popup", "notification"].include?(reminder["method"])
      end

      # Only set custom reminders if we have at least one valid reminder
      if valid_reminders.any?
        google_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
          use_default: false,
          overrides: valid_reminders.map do |reminder|
            # Normalize "notification" to "popup" for Google Calendar API
            method = reminder["method"] == "notification" ? "popup" : reminder["method"]
            # Convert time and type to minutes
            minutes = convert_time_to_minutes(reminder["time"], reminder["type"])
            Google::Apis::CalendarV3::EventReminder.new(
              reminder_method: method,
              minutes: minutes
            )
          end
        )
      end
    end

    # Apply visibility if present
    google_event.visibility = event_data[:visibility] if event_data[:visibility].present?

    created_event = service.insert_event(calendar_id, google_event)

    # Save the event ID in the database
    google_calendar.google_calendar_events.create!(
      google_event_id: created_event.id,
      meeting_time_id: course_event[:meeting_time_id],
      summary: event_data[:summary],
      location: event_data[:location],
      start_time: event_data[:start_time],
      end_time: event_data[:end_time],
      recurrence: event_data[:recurrence],
      event_data_hash: GoogleCalendarEvent.generate_data_hash(event_data),
      last_synced_at: Time.current
    )

  end

  def update_event_in_calendar(service, google_calendar, db_event, course_event, force: false, preference_resolver: nil, template_renderer: nil)
    # Use hash-based change detection for efficiency (unless forced)
    unless force || db_event.data_changed?(course_event)
      db_event.mark_synced!
      return
    end

    calendar_id = google_calendar.google_calendar_id

    # IMPORTANT: Check if user made edits in Google Calendar before overwriting
    # Skip this check when force=true (e.g., user changed preferences and expects them to be applied)
    unless force
      # Fetch the current state from Google Calendar to detect user edits
      begin
        current_gcal_event = service.get_event(calendar_id, db_event.google_event_id)

        # Check if user edited the event in Google Calendar
        if user_edited_event?(db_event, current_gcal_event)
          Rails.logger.info "User edited event in Google Calendar: #{db_event.google_event_id}. Preserving user changes."

          # Update local DB with user's Google Calendar edits
          update_db_from_gcal_event(db_event, current_gcal_event)

          # Mark as synced since we just pulled the latest from Google Calendar
          db_event.mark_synced!
          return
        end
      rescue Google::Apis::ClientError => e
        # If event doesn't exist in Google Calendar, we'll recreate it below
        raise unless e.status_code == 404

        Rails.logger.warn "Event not found in Google Calendar, recreating: #{db_event.google_event_id}"
        db_event.destroy
        create_event_in_calendar(service, google_calendar, course_event)
        return
      end
    end

    # No user edits detected, proceed with normal update from our system
    meeting_time = MeetingTime.includes(course: :faculties).find_by(id: course_event[:meeting_time_id])

    # Apply user preferences to event data
    event_data = apply_preferences_to_event(meeting_time, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

    # Ensure times are in Eastern timezone
    start_time_et = event_data[:start_time].in_time_zone("America/New_York")
    end_time_et = event_data[:end_time].in_time_zone("America/New_York")

    google_event = Google::Apis::CalendarV3::Event.new(
      summary: event_data[:summary],
      description: event_data[:description],
      location: event_data[:location],
      start: {
        date_time: start_time_et.iso8601,
        time_zone: "America/New_York"
      },
      end: {
        date_time: end_time_et.iso8601,
        time_zone: "America/New_York"
      },
      color_id: event_data[:color_id]&.to_s,
      recurrence: event_data[:recurrence]
    )

    # Apply reminders if present and valid
    if event_data[:reminder_settings].present? && event_data[:reminder_settings].is_a?(Array)
      # Filter to only valid reminders with required fields
      # Accept "notification" as alias for "popup"
      valid_reminders = event_data[:reminder_settings].select do |reminder|
        reminder.is_a?(Hash) &&
          reminder["method"].present? &&
          reminder["time"].present? &&
          reminder["type"].present? &&
          ["email", "popup", "notification"].include?(reminder["method"])
      end

      # Only set custom reminders if we have at least one valid reminder
      if valid_reminders.any?
        google_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
          use_default: false,
          overrides: valid_reminders.map do |reminder|
            # Normalize "notification" to "popup" for Google Calendar API
            method = reminder["method"] == "notification" ? "popup" : reminder["method"]
            # Convert time and type to minutes
            minutes = convert_time_to_minutes(reminder["time"], reminder["type"])
            Google::Apis::CalendarV3::EventReminder.new(
              reminder_method: method,
              minutes: minutes
            )
          end
        )
      end
    end

    # Apply visibility if present
    google_event.visibility = event_data[:visibility] if event_data[:visibility].present?

    service.update_event(calendar_id, db_event.google_event_id, google_event)

    # Update the database record with new data and hash
    db_event.update!(
      summary: event_data[:summary],
      location: event_data[:location],
      start_time: event_data[:start_time],
      end_time: event_data[:end_time],
      recurrence: event_data[:recurrence],
      event_data_hash: GoogleCalendarEvent.generate_data_hash(event_data),
      last_synced_at: Time.current
    )
  end

  def delete_event_from_calendar(service, google_calendar, db_event)
    calendar_id = google_calendar.google_calendar_id

    service.delete_event(calendar_id, db_event.google_event_id)
    db_event.destroy
  rescue Google::Apis::ClientError => e
    # If event doesn't exist, just remove from database
    raise unless e.status_code == 404

    Rails.logger.warn "Event not found in Google Calendar, removing from database: #{db_event.google_event_id}"
    db_event.destroy



  end

  # Check if user edited the event in Google Calendar
  # Compares our local DB state with the current Google Calendar state
  def user_edited_event?(db_event, gcal_event)
    # Extract data from Google Calendar event
    gcal_summary = gcal_event.summary
    gcal_location = gcal_event.location

    # Parse Google Calendar times to Ruby Time objects in Eastern timezone
    gcal_start_time = parse_gcal_time(gcal_event.start)
    gcal_end_time = parse_gcal_time(gcal_event.end)

    # Extract recurrence from Google Calendar event
    gcal_recurrence = gcal_event.recurrence

    # Compare with our local DB state
    # If any field differs, the user must have edited it
    summary_changed = gcal_summary != db_event.summary
    location_changed = gcal_location != db_event.location

    # Time comparison - handle nil cases properly
    start_time_changed = if gcal_start_time.nil? || db_event.start_time.nil?
                           gcal_start_time != db_event.start_time
                         else
                           gcal_start_time.to_i != db_event.start_time.to_i
                         end

    end_time_changed = if gcal_end_time.nil? || db_event.end_time.nil?
                         gcal_end_time != db_event.end_time
                       else
                         gcal_end_time.to_i != db_event.end_time.to_i
                       end

    recurrence_changed = normalize_recurrence(gcal_recurrence) != normalize_recurrence(db_event.recurrence)

    # If any field changed, user edited the event
    if summary_changed || location_changed || start_time_changed || end_time_changed || recurrence_changed
      Rails.logger.info "User edit detected - Summary: #{summary_changed}, Location: #{location_changed}, " \
                        "Start: #{start_time_changed}, End: #{end_time_changed}, Recurrence: #{recurrence_changed}"
      return true
    end

    false
  end

  # Update local DB with user's edits from Google Calendar
  def update_db_from_gcal_event(db_event, gcal_event)
    # Extract data from Google Calendar event
    summary = gcal_event.summary
    location = gcal_event.location
    start_time = parse_gcal_time(gcal_event.start)
    end_time = parse_gcal_time(gcal_event.end)
    recurrence = gcal_event.recurrence

    # Build event data for hash generation
    event_data = {
      summary: summary,
      location: location,
      start_time: start_time,
      end_time: end_time,
      recurrence: recurrence
    }

    # Update the database with Google Calendar data
    db_event.update!(
      summary: summary,
      location: location,
      start_time: start_time,
      end_time: end_time,
      recurrence: recurrence,
      event_data_hash: GoogleCalendarEvent.generate_data_hash(event_data),
      last_synced_at: Time.current
    )

    Rails.logger.info "Updated local DB with user's Google Calendar edits for event: #{db_event.google_event_id}"
  end

  # Parse Google Calendar event time to Ruby Time object
  def parse_gcal_time(time_obj)
    return nil unless time_obj

    if time_obj.date_time
      # date_time can be either a DateTime object or a string depending on the API gem version
      # Convert to Time and ensure it's in Eastern timezone
      if time_obj.date_time.is_a?(String)
        Time.zone.parse(time_obj.date_time).in_time_zone("America/New_York")
      else
        time_obj.date_time.in_time_zone("America/New_York")
      end
    elsif time_obj.date
      # All-day event - not currently supported but handle gracefully
      # date can be either a Date object or a string
      if time_obj.date.is_a?(String)
        Time.zone.parse(time_obj.date).in_time_zone("America/New_York")
      else
        time_obj.date.in_time_zone("America/New_York")
      end
    end
  end

  # Normalize recurrence arrays for comparison
  def normalize_recurrence(recurrence)
    return nil if recurrence.blank?

    # Ensure it's an array and sort for consistent comparison
    Array(recurrence).compact.sort
  end

  def apply_preferences_to_event(meeting_time, course_event, preference_resolver: nil, template_renderer: nil)
    return course_event unless meeting_time

    # Use provided instances or create new ones (for backward compatibility)
    resolver = preference_resolver || PreferenceResolver.new(user)
    renderer = template_renderer || CalendarTemplateRenderer.new

    # Resolve preferences for this meeting time
    prefs = resolver.resolve_for(meeting_time)

    # Build template context
    context = CalendarTemplateRenderer.build_context_from_meeting_time(meeting_time)

    # Apply preferences to event data
    event_data = course_event.dup

    # Render title template if present
    if prefs[:title_template].present?
      event_data[:summary] = renderer.render(prefs[:title_template], context)
    end

    # Render description template if present
    if prefs[:description_template].present?
      event_data[:description] = renderer.render(prefs[:description_template], context)
    end

    # Render location template if present
    if prefs[:location_template].present?
      event_data[:location] = renderer.render(prefs[:location_template], context)
    end

    # Apply reminder settings
    event_data[:reminder_settings] = prefs[:reminder_settings] if prefs[:reminder_settings].present?

    # Apply color - convert hex codes to numeric IDs if needed
    if prefs[:color_id].present?
      event_data[:color_id] = normalize_color_id(prefs[:color_id])
    else
      event_data[:color_id] = nil
    end

    # Apply visibility
    event_data[:visibility] = prefs[:visibility] if prefs[:visibility].present?

    event_data
  end

  # Normalize color ID - convert hex codes to numeric IDs for Google Calendar API
  # @param color_id_or_hex [Integer, String] Either a numeric ID (1-11) or hex code
  # @return [Integer, nil] Numeric color ID (1-11) or nil
  def normalize_color_id(color_id_or_hex)
    return nil if color_id_or_hex.blank?

    # If it's already a number (Integer or numeric String), use it directly
    if color_id_or_hex.is_a?(Integer)
      return color_id_or_hex if (1..11).cover?(color_id_or_hex)

      return nil
    end

    # If it's a string that looks like a number, convert it
    if color_id_or_hex.is_a?(String) && color_id_or_hex.match?(/\A\d+\z/)
      id = color_id_or_hex.to_i
      return id if (1..11).cover?(id)

      return nil
    end

    # If it's a hex code, convert it to numeric ID
    if color_id_or_hex.is_a?(String) && color_id_or_hex.start_with?("#")
      normalized_hex = color_id_or_hex.downcase
      GoogleColors::EVENT_MAP.each do |key, hex_value|
        return key if key.is_a?(Integer) && hex_value == normalized_hex
      end
    end

    nil
  end


  # Convert reminder time and type to minutes for Google Calendar API
  # @param time [String] The time value (e.g., "30", "2", "1")
  # @param type [String] The time unit ("minutes", "hours", "days")
  # @return [Integer] The time in minutes
  def convert_time_to_minutes(time, type)
    time_value = time.to_f

    case type
    when "minutes"
      time_value.to_i
    when "hours"
      (time_value * 60).to_i
    when "days"
      (time_value * 1440).to_i
    else
      time_value.to_i # default to minutes
    end
  end

end
