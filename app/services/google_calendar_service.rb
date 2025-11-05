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
    current_meeting_time_ids = events.map { |e| e[:meeting_time_id] }.compact

    # Delete events that are no longer needed
    events_to_delete = existing_events.reject { |mt_id, _| current_meeting_time_ids.include?(mt_id) }
    events_to_delete.each do |_, cal_event|
      delete_event_from_calendar(service, google_calendar, cal_event)
    end

    # Stats for logging
    stats = { created: 0, updated: 0, skipped: 0 }

    # Create or update events
    events.each do |event|
      meeting_time_id = event[:meeting_time_id]
      existing_event = existing_events[meeting_time_id]

      if existing_event
        # Update existing event if needed (or skip if no changes and not forced)
        if force || existing_event.data_changed?(event)
          update_event_in_calendar(service, google_calendar, existing_event, event, force: force)
          stats[:updated] += 1
        else
          existing_event.mark_synced!
          stats[:skipped] += 1
        end
      else
        # Create new event
        create_event_in_calendar(service, google_calendar, event)
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

    stats = { created: 0, updated: 0, skipped: 0 }

    events.each do |event|
      meeting_time_id = event[:meeting_time_id]
      existing_event = google_calendar.google_calendar_events.find_by(
        meeting_time_id: meeting_time_id
      )

      if existing_event
        if force || existing_event.data_changed?(event)
          update_event_in_calendar(service, google_calendar, existing_event, event, force: force)
          stats[:updated] += 1
        else
          existing_event.mark_synced!
          stats[:skipped] += 1
        end
      else
        create_event_in_calendar(service, google_calendar, event)
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
    service = service_account_calendar_service
    service.delete_calendar(calendar_id)
  end

  def get_available_colors
    service = service_account_calendar_service
    colors = service.get_color

    colors
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

    calendar = Google::Apis::CalendarV3::Calendar.new(
      summary: "WIT Courses",
      description: "Course schedule for #{user.email}.\nCreated and Updated by WIT Course Calendar App.",
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
        role: "reader" # reader access
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
      role: "editor" # editor access
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

    service.insert_calendar_list(calendar_list_entry)
  rescue Google::Apis::ClientError => e
    # Ignore if already in list
    raise unless e.status_code == 409
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

  def create_event_in_calendar(service, google_calendar, course_event)
    calendar_id = google_calendar.google_calendar_id

    # Ensure times are in Eastern timezone
    start_time_et = course_event[:start_time].in_time_zone("America/New_York")
    end_time_et = course_event[:end_time].in_time_zone("America/New_York")

    event = Google::Apis::CalendarV3::Event.new(
      summary: course_event[:summary],
      location: course_event[:location],
      start: {
        date_time: start_time_et.iso8601,
        time_zone: "America/New_York"
      },
      end: {
        date_time: end_time_et.iso8601,
        time_zone: "America/New_York"
      },
      color_id: get_color_for_meeting_time(course_event[:meeting_time_id]),
      recurrence: course_event[:recurrence]
    )

    created_event = service.insert_event(calendar_id, event)

    # Save the event ID in the database
    google_calendar.google_calendar_events.create!(
      user: user,
      google_event_id: created_event.id,
      meeting_time_id: course_event[:meeting_time_id],
      summary: course_event[:summary],
      location: course_event[:location],
      start_time: course_event[:start_time],
      end_time: course_event[:end_time],
      recurrence: course_event[:recurrence],
      event_data_hash: GoogleCalendarEvent.generate_data_hash(course_event),
      last_synced_at: Time.current
    )

  end

  def update_event_in_calendar(service, google_calendar, db_event, course_event, force: false)
    # Use hash-based change detection for efficiency (unless forced)
    unless force || db_event.data_changed?(course_event)
      db_event.mark_synced!
      return
    end

    calendar_id = google_calendar.google_calendar_id

    # IMPORTANT: Check if user made edits in Google Calendar before overwriting
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
      if e.status_code == 404
        Rails.logger.warn "Event not found in Google Calendar, recreating: #{db_event.google_event_id}"
        db_event.destroy
        create_event_in_calendar(service, google_calendar, course_event)
        return
      else
        raise
      end
    end

    # No user edits detected, proceed with normal update from our system
    # Ensure times are in Eastern timezone
    start_time_et = course_event[:start_time].in_time_zone("America/New_York")
    end_time_et = course_event[:end_time].in_time_zone("America/New_York")

    event = Google::Apis::CalendarV3::Event.new(
      summary: course_event[:summary],
      location: course_event[:location],
      start: {
        date_time: start_time_et.iso8601,
        time_zone: "America/New_York"
      },
      end: {
        date_time: end_time_et.iso8601,
        time_zone: "America/New_York"
      },
      color_id: get_color_for_meeting_time(course_event[:meeting_time_id]),
      recurrence: course_event[:recurrence]
    )

    service.update_event(calendar_id, db_event.google_event_id, event)

    # Update the database record with new data and hash
    db_event.update!(
      summary: course_event[:summary],
      location: course_event[:location],
      start_time: course_event[:start_time],
      end_time: course_event[:end_time],
      recurrence: course_event[:recurrence],
      event_data_hash: GoogleCalendarEvent.generate_data_hash(course_event),
      last_synced_at: Time.current
    )
  end

  def delete_event_from_calendar(service, google_calendar, db_event)
    calendar_id = google_calendar.google_calendar_id

    service.delete_event(calendar_id, db_event.google_event_id)
    db_event.destroy
  rescue Google::Apis::ClientError => e
    # If event doesn't exist, just remove from database
    if e.status_code == 404
      Rails.logger.warn "Event not found in Google Calendar, removing from database: #{db_event.google_event_id}"
      db_event.destroy
    else
      raise
    end
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
      # Parse datetime string to Time object in Eastern timezone
      # date_time is already a string in ISO 8601 format from Google Calendar API
      Time.zone.parse(time_obj.date_time).in_time_zone("America/New_York")
    elsif time_obj.date
      # All-day event - not currently supported but handle gracefully
      # date is already a string in 'YYYY-MM-DD' format from Google Calendar API
      Time.zone.parse(time_obj.date).in_time_zone("America/New_York")
    end
  end
  
  # Normalize recurrence arrays for comparison
  def normalize_recurrence(recurrence)
    return nil if recurrence.nil? || recurrence.empty?
    
    # Ensure it's an array and sort for consistent comparison
    Array(recurrence).compact.sort
  end

  def get_color_for_meeting_time(meeting_time_id)
    # find the meeting time by id as meeting_time has a event_color method
    meeting_time = MeetingTime.find_by(id: meeting_time_id)
    return nil unless meeting_time

    # Map the event color to Google Calendar color IDs
    case meeting_time.event_color
    when GoogleColors::EVENT_MAP[5]
      "5"  # Gold
    when GoogleColors::EVENT_MAP[11]
      "11" # Ruby Red
    when GoogleColors::EVENT_MAP[8]
      "8"  # Platinum
    else
      nil  # Default color
    end
  end

end
