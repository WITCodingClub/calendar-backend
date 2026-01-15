# frozen_string_literal: true

class GoogleCalendarService
  include GoogleApiRateLimiter

  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def create_or_get_course_calendar
    # Check if ANY of the user's OAuth credentials already has a GoogleCalendar
    google_calendar = GoogleCalendar.for_user(user).first
    newly_created = false

    # Create calendar if it doesn't exist for any OAuth credential
    if google_calendar.blank?
      google_api_calendar = create_calendar_with_service_account
      # Use the primary Google credential or first available to create the calendar
      primary_credential = user.google_credential || user.google_credentials.first
      raise "No Google OAuth credentials found for user" unless primary_credential

      google_calendar = primary_credential.create_google_calendar!(
        google_calendar_id: google_api_calendar.id,
        summary: google_api_calendar.summary,
        description: google_api_calendar.description,
        time_zone: google_api_calendar.time_zone
      )
      newly_created = true
    end

    calendar_id = google_calendar.google_calendar_id

    # Share calendar with all g_cal emails
    share_calendar_with_user(calendar_id)

    # Add calendar to each OAuth'd email's Google Calendar list
    add_calendar_to_all_oauth_users(calendar_id)

    # Trigger initial sync for newly created calendars
    if newly_created && user.enrollments.any?
      GoogleCalendarSyncJob.perform_later(user, force: true)
    end

    calendar_id
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to create Google Calendar: #{e.message}"
    raise "Failed to create course calendar: #{e.message}"
  end

  def update_calendar_events(events, force: false)
    # Use user's OAuth credentials so reminders are visible to the user
    service = user_calendar_service
    google_calendar = GoogleCalendar.for_user(user).first
    return { created: 0, updated: 0, skipped: 0 } unless google_calendar

    calendar_id = google_calendar.google_calendar_id

    # Get existing calendar events from database
    # Index by a composite key that handles meeting_time_id, final_exam_id, and university_event_id
    # Group duplicates and keep only the most recent one to handle existing duplicates
    all_existing_events = google_calendar.google_calendar_events.to_a

    # Detect and handle duplicates
    existing_events = {}
    duplicates_to_delete = []

    all_existing_events.each do |e|
      event_key = if e.meeting_time_id
                    "mt_#{e.meeting_time_id}"
                  elsif e.final_exam_id
                    "fe_#{e.final_exam_id}"
                  else
                    "ue_#{e.university_calendar_event_id}"
                  end

      if existing_events[event_key]
        # Duplicate found - keep the newer one, mark old one for deletion
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

    # Delete duplicates from both database and Google Calendar
    if duplicates_to_delete.any?
      Rails.logger.info "Cleaning up #{duplicates_to_delete.size} duplicate calendar events"
      with_batch_throttling(duplicates_to_delete) do |cal_event|
        delete_event_from_calendar(service, google_calendar, cal_event)
      end
    end

    # Track which events are in the new events list (meeting times, finals, and university events)
    current_event_keys = events.map do |e|
      if e[:meeting_time_id]
        "mt_#{e[:meeting_time_id]}"
      elsif e[:final_exam_id]
        "fe_#{e[:final_exam_id]}"
      elsif e[:university_calendar_event_id]
        "ue_#{e[:university_calendar_event_id]}"
      end
    end.compact

    # Delete events that are no longer needed
    events_to_delete = existing_events.except(*current_event_keys)
    # Use batch throttling when deleting multiple events to avoid rate limits
    with_batch_throttling(events_to_delete.values) do |cal_event|
      delete_event_from_calendar(service, google_calendar, cal_event)
    end

    # Stats for logging
    stats = { created: 0, updated: 0, skipped: 0 }

    # Initialize shared preference resolver and template renderer to avoid re-creating per event
    preference_resolver = PreferenceResolver.new(user)
    template_renderer = CalendarTemplateRenderer.new

    # Create or update events
    events.each do |event|
      event_key = if event[:meeting_time_id]
                    "mt_#{event[:meeting_time_id]}"
                  elsif event[:final_exam_id]
                    "fe_#{event[:final_exam_id]}"
                  elsif event[:university_calendar_event_id]
                    "ue_#{event[:university_calendar_event_id]}"
                  end
      existing_event = existing_events[event_key]

      if existing_event
        # Apply preferences to get the full event data for comparison
        # Handle meeting times, final exams, and university events
        syncable = if event[:meeting_time_id]
                     MeetingTime.includes(course: :faculties).find_by(id: event[:meeting_time_id])
                   elsif event[:final_exam_id]
                     FinalExam.includes(course: :faculties).find_by(id: event[:final_exam_id])
                   elsif event[:university_calendar_event_id]
                     UniversityCalendarEvent.find_by(id: event[:university_calendar_event_id])
                   else
                     raise "Unknown event type - missing meeting_time_id, final_exam_id, or university_calendar_event_id"
                   end
        event_with_preferences = apply_preferences_to_event(syncable, event, preference_resolver: preference_resolver, template_renderer: template_renderer)

        # Update existing event if needed (or skip if no changes and not forced)
        if force || existing_event.data_changed?(event_with_preferences)
          result = update_event_in_calendar(service, google_calendar, existing_event, event_with_preferences, force: force, preference_resolver: preference_resolver, template_renderer: template_renderer)
          stats[:updated] += 1 if result == :updated
          stats[:skipped] += 1 if result == :skipped_user_edit
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

    # Calculate optimization effectiveness
    total_processed = stats[:created] + stats[:updated] + stats[:skipped]
    skip_percentage = total_processed > 0 ? (stats[:skipped].to_f / total_processed * 100).round(2) : 0

    Rails.logger.info({
      message: "Calendar sync completed",
      user_id: user.id,
      events_created: stats[:created],
      events_updated: stats[:updated],
      events_skipped: stats[:skipped],
      total_processed: total_processed,
      skip_percentage: skip_percentage,
      optimization_effective: skip_percentage > 0
    }.to_json)

    stats
  end

  # Update only specific events (for partial syncs)
  def update_specific_events(events, force: false)
    # Use user's OAuth credentials so reminders are visible to the user
    service = user_calendar_service
    google_calendar = GoogleCalendar.for_user(user).first
    unless google_calendar
      Rails.logger.warn({
        message: "Cannot update events - no Google Calendar found",
        user_id: user&.id,
        has_google_credential: user&.google_credential.present?,
        event_count: events.size
      }.to_json)
      return { created: 0, updated: 0, skipped: 0 }
    end

    # Preload existing events to avoid N+1 queries
    # rubocop:disable Rails/Pluck -- events is an array of hashes, not an ActiveRecord relation
    meeting_time_ids = events.map { |e| e[:meeting_time_id] }.compact
    final_exam_ids = events.map { |e| e[:final_exam_id] }.compact
    university_event_ids = events.map { |e| e[:university_calendar_event_id] }.compact
    # rubocop:enable Rails/Pluck

    existing_events_query = google_calendar.google_calendar_events
    conditions = []
    conditions << existing_events_query.where(meeting_time_id: meeting_time_ids) if meeting_time_ids.any?
    conditions << existing_events_query.where(final_exam_id: final_exam_ids) if final_exam_ids.any?
    conditions << existing_events_query.where(university_calendar_event_id: university_event_ids) if university_event_ids.any?

    existing_events_query = conditions.reduce { |query, condition| query.or(condition) } || existing_events_query

    existing_events = existing_events_query.index_by do |e|
      if e.meeting_time_id
        "mt_#{e.meeting_time_id}"
      elsif e.final_exam_id
        "fe_#{e.final_exam_id}"
      else
        "ue_#{e.university_calendar_event_id}"
      end
    end

    # Initialize shared preference resolver and template renderer to avoid re-creating per event
    preference_resolver = PreferenceResolver.new(user)
    template_renderer = CalendarTemplateRenderer.new

    stats = { created: 0, updated: 0, skipped: 0 }

    events.each do |event|
      event_key = if event[:meeting_time_id]
                    "mt_#{event[:meeting_time_id]}"
                  elsif event[:final_exam_id]
                    "fe_#{event[:final_exam_id]}"
                  elsif event[:university_calendar_event_id]
                    "ue_#{event[:university_calendar_event_id]}"
                  end
      existing_event = existing_events[event_key]

      if existing_event
        # Apply preferences to get the full event data for comparison
        syncable = if event[:meeting_time_id]
                     MeetingTime.includes(course: :faculties).find_by(id: event[:meeting_time_id])
                   elsif event[:final_exam_id]
                     FinalExam.includes(course: :faculties).find_by(id: event[:final_exam_id])
                   elsif event[:university_calendar_event_id]
                     UniversityCalendarEvent.find_by(id: event[:university_calendar_event_id])
                   else
                     raise "Unknown event type - missing meeting_time_id, final_exam_id, or university_calendar_event_id"
                   end
        event_with_preferences = apply_preferences_to_event(syncable, event, preference_resolver: preference_resolver, template_renderer: template_renderer)

        if force || existing_event.data_changed?(event_with_preferences)
          update_event_in_calendar(service, google_calendar, existing_event, event_with_preferences, force: force, preference_resolver: preference_resolver, template_renderer: template_renderer)
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
    with_rate_limit_handling do
      service.list_calendar_lists
    end
  end

  def delete_calendar(calendar_id)
    # First, get the calendar to access its user
    google_calendar = GoogleCalendar.find_by(google_calendar_id: calendar_id)

    if google_calendar
      # Remove calendar from all OAuth'd users' calendar lists (sidebar)
      calendar_user = google_calendar.user
      credentials = calendar_user.google_credentials.to_a

      # Use batch throttling when removing from multiple users
      with_batch_throttling(credentials) do |credential|
        remove_calendar_from_user_list_for_email(calendar_id, credential.email)
      end
    end

    # Then delete the actual calendar
    service = service_account_calendar_service
    with_rate_limit_handling do
      service.delete_calendar(calendar_id)
    end
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

    with_rate_limit_handling do
      service.insert_calendar(calendar)
    end
  end

  def share_calendar_with_user(calendar_id)
    service = service_account_calendar_service
    emails = user.emails.where(g_cal: true).to_a

    # Use batch throttling to avoid rate limits when sharing with multiple emails
    with_batch_throttling(emails) do |email_record|
      rule = Google::Apis::CalendarV3::AclRule.new(
        scope: {
          type: "user",
          value: email_record.email
        },
        role: "owner" # owner access (full permissions including notifications)
      )

      begin
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
      role: "owner" # owner access (full permissions including notifications)
    )

    with_rate_limit_handling do
      service.insert_acl(
        calendar_id,
        rule,
        send_notifications: false
      )
    end
  rescue Google::Apis::ClientError => e
    # Ignore if user already has access
    raise unless e.status_code == 409

  end

  def unshare_calendar_with_email(calendar_id, email_id)
    service = service_account_calendar_service
    email = Email.find_by(email: email_id, user_id: user.id)
    return unless email&.g_cal

    # Find the ACL entry for the email
    acl_list = with_rate_limit_handling do
      service.list_acls(calendar_id)
    end
    acl_entry = acl_list.items.find { |item| item.scope.type == "user" && item.scope.value == email.email }
    return unless acl_entry

    with_rate_limit_handling do
      service.delete_acl(calendar_id, acl_entry.id)
    end
  rescue Google::Apis::ClientError => e
    # Ignore if user doesn't have access
    raise unless e.status_code == 404
  end

  def add_calendar_to_all_oauth_users(calendar_id)
    # Add calendar to each OAuth'd email's Google Calendar list
    credentials = user.google_credentials.to_a

    # Use batch throttling to avoid rate limits when adding to multiple users
    with_batch_throttling(credentials) do |credential|
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
      color_id: "7",
      selected: true,
      hidden: false
    )

    retries = 0
    max_retries = 3

    begin
      with_rate_limit_handling do
        service.insert_calendar_list(calendar_list_entry)
      end
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
    with_rate_limit_handling do
      service.delete_calendar_list(calendar_id)
    end
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
    events = with_rate_limit_handling do
      service.list_events(calendar_id)
    end

    # Delete each event with batch throttling
    with_batch_throttling(events.items) do |event|
      begin
        service.delete_event(calendar_id, event.id)
      rescue Google::Apis::ClientError => e
        Rails.logger.warn "Failed to delete event: #{e.message}"
      end
    end
  end

  def create_event_in_calendar(service, google_calendar, course_event, preference_resolver: nil, template_renderer: nil)
    calendar_id = google_calendar.google_calendar_id

    # Handle both meeting times and final exams
    syncable = if course_event[:meeting_time_id]
                 MeetingTime.includes(course: :faculties).find_by(id: course_event[:meeting_time_id])
               else
                 FinalExam.includes(course: :faculties).find_by(id: course_event[:final_exam_id])
               end

    # Apply user preferences to event data
    event_data = apply_preferences_to_event(syncable, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

    # Build the Google event object
    google_event = Google::Apis::CalendarV3::Event.new(
      summary: event_data[:summary],
      description: event_data[:description],
      location: event_data[:location],
      color_id: event_data[:color_id]&.to_s
    )

    # Handle all-day events differently than timed events
    if event_data[:all_day]
      # For all-day events, use date format (not date_time)
      # Google Calendar API uses exclusive end dates for all-day events
      # (the end date is the day AFTER the last day of the event)
      google_event.start = { date: event_data[:start_time].to_date.to_s }
      google_event.end = { date: (event_data[:end_time].to_date + 1.day).to_s }
    else
      # For timed events, use date_time format with timezone
      start_time_et = event_data[:start_time].in_time_zone("America/New_York")
      end_time_et = event_data[:end_time].in_time_zone("America/New_York")

      google_event.start = {
        date_time: start_time_et.iso8601,
        time_zone: "America/New_York"
      }
      google_event.end = {
        date_time: end_time_et.iso8601,
        time_zone: "America/New_York"
      }
    end

    # Only set recurrence if it has a value - Google API gem fails on nil
    google_event.recurrence = event_data[:recurrence] if event_data[:recurrence].present?

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

    created_event = with_rate_limit_handling do
      service.insert_event(calendar_id, google_event)
    end

    # Save the event ID in the database
    event_attributes = {
      google_event_id: created_event.id,
      summary: event_data[:summary],
      location: event_data[:location],
      start_time: event_data[:start_time],
      end_time: event_data[:end_time],
      recurrence: event_data[:recurrence],
      event_data_hash: GoogleCalendarEvent.generate_data_hash(event_data),
      last_synced_at: Time.current
    }

    # Add only one event type association
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
    # Use hash-based change detection for efficiency (unless forced)
    unless force || db_event.data_changed?(course_event)
      db_event.mark_synced!
      return :skipped_no_change
    end

    calendar_id = google_calendar.google_calendar_id
    current_gcal_event = nil
    newly_edited_fields = []

    # IMPORTANT: Check if user made edits in Google Calendar before overwriting
    # Skip this check when force=true (e.g., user changed preferences and expects them to be applied)
    unless force
      # Fetch the current state from Google Calendar to detect user edits
      begin
        current_gcal_event = with_rate_limit_handling do
          service.get_event(calendar_id, db_event.google_event_id)
        end

        # Detect which specific fields the user edited
        newly_edited_fields = detect_user_edited_fields(db_event, current_gcal_event)

        # Also check for recurrence changes (not tracked but still means user edit)
        gcal_recurrence = current_gcal_event.recurrence
        recurrence_changed = normalize_recurrence(gcal_recurrence) != normalize_recurrence(db_event.recurrence)

        if recurrence_changed
          # If recurrence changed, treat entire event as user-edited and preserve it
          Rails.logger.info "User edited recurrence in Google Calendar: #{db_event.google_event_id}. Preserving user changes."

          Rails.logger.info({
            message: "Event skipped - user edited recurrence in Google Calendar",
            user_id: user.id,
            google_event_id: db_event.google_event_id,
            meeting_time_id: db_event.meeting_time_id,
            reason: "user_edit_recurrence"
          }.to_json)

          update_db_from_gcal_event(db_event, current_gcal_event)
          db_event.mark_synced!
          return :skipped_user_edit
        end
      rescue Google::Apis::ClientError => e
        # If event doesn't exist in Google Calendar, we'll recreate it below
        raise unless e.status_code == 404

        Rails.logger.warn({
          message: "Event not found in Google Calendar, recreating",
          user_id: user.id,
          google_event_id: db_event.google_event_id,
          meeting_time_id: db_event.meeting_time_id
        }.to_json)

        db_event.destroy
        create_event_in_calendar(service, google_calendar, course_event)
        return :recreated
      end
    end

    # Determine the syncable object (meeting_time, final_exam, or university event)
    syncable = if course_event[:meeting_time_id]
                 MeetingTime.includes(course: :faculties).find_by(id: course_event[:meeting_time_id])
               elsif course_event[:final_exam_id]
                 FinalExam.includes(course: :faculties).find_by(id: course_event[:final_exam_id])
               elsif course_event[:university_calendar_event_id]
                 UniversityCalendarEvent.find_by(id: course_event[:university_calendar_event_id])
               end

    # Apply user preferences to event data
    # Note: course_event may already have preferences applied, but re-applying is safe (idempotent)
    event_data = apply_preferences_to_event(syncable, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

    # Get all user-edited fields (previously tracked + newly detected)
    all_edited_fields = if force
                          [] # Force sync clears all user edits
                        else
                          ((db_event.user_edited_fields || []) + newly_edited_fields).uniq
                        end

    # Merge user-edited values with system-generated values
    # User-edited fields preserve the Google Calendar value, system fields use our generated value
    merged_event_data = event_data.dup
    if all_edited_fields.any? && current_gcal_event
      all_edited_fields.each do |field|
        case field
        when "summary"
          merged_event_data[:summary] = current_gcal_event.summary
        when "location"
          merged_event_data[:location] = current_gcal_event.location
        when "description"
          merged_event_data[:description] = current_gcal_event.description
        when "start_time"
          merged_event_data[:start_time] = parse_gcal_time(current_gcal_event.start)
        when "end_time"
          merged_event_data[:end_time] = parse_gcal_time(current_gcal_event.end)
        end
      end
    end

    # Build the Google event object with merged data
    google_event = Google::Apis::CalendarV3::Event.new(
      summary: merged_event_data[:summary],
      description: merged_event_data[:description],
      location: merged_event_data[:location],
      color_id: merged_event_data[:color_id]&.to_s
    )

    # Handle all-day events differently than timed events
    if merged_event_data[:all_day]
      # For all-day events, use date format (not date_time)
      # Google Calendar API uses exclusive end dates for all-day events
      # (the end date is the day AFTER the last day of the event)
      google_event.start = { date: merged_event_data[:start_time].to_date.to_s }
      google_event.end = { date: (merged_event_data[:end_time].to_date + 1.day).to_s }
    else
      # For timed events, use date_time format with timezone
      start_time_et = merged_event_data[:start_time].in_time_zone("America/New_York")
      end_time_et = merged_event_data[:end_time].in_time_zone("America/New_York")

      google_event.start = {
        date_time: start_time_et.iso8601,
        time_zone: "America/New_York"
      }
      google_event.end = {
        date_time: end_time_et.iso8601,
        time_zone: "America/New_York"
      }
    end

    # Only set recurrence if it has a value - Google API gem fails on nil
    google_event.recurrence = merged_event_data[:recurrence] if merged_event_data[:recurrence].present?

    # Apply reminders if present and valid
    if merged_event_data[:reminder_settings].present? && merged_event_data[:reminder_settings].is_a?(Array)
      # Filter to only valid reminders with required fields
      # Accept "notification" as alias for "popup"
      valid_reminders = merged_event_data[:reminder_settings].select do |reminder|
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
    google_event.visibility = merged_event_data[:visibility] if merged_event_data[:visibility].present?

    with_rate_limit_handling do
      service.update_event(calendar_id, db_event.google_event_id, google_event)
    end

    # Update the database record with merged data and hash
    db_event.update!(
      summary: merged_event_data[:summary],
      location: merged_event_data[:location],
      start_time: merged_event_data[:start_time],
      end_time: merged_event_data[:end_time],
      recurrence: merged_event_data[:recurrence],
      event_data_hash: GoogleCalendarEvent.generate_data_hash(merged_event_data),
      last_synced_at: Time.current,
      user_edited_fields: all_edited_fields.any? ? all_edited_fields : nil
    )

    # Log detailed update information (especially for color changes)
    Rails.logger.info({
      message: "Google Calendar event updated",
      user_id: user.id,
      google_event_id: db_event.google_event_id,
      meeting_time_id: db_event.meeting_time_id,
      forced: force,
      color_id: merged_event_data[:color_id],
      has_color: merged_event_data[:color_id].present?,
      user_edited_fields: all_edited_fields
    }.to_json)

    :updated
  end

  def delete_event_from_calendar(service, google_calendar, db_event)
    calendar_id = google_calendar.google_calendar_id

    with_rate_limit_handling do
      service.delete_event(calendar_id, db_event.google_event_id)
    end
    db_event.destroy
  rescue Google::Apis::ClientError => e
    # If event doesn't exist, just remove from database
    raise unless e.status_code == 404

    Rails.logger.warn({
      message: "Event not found in Google Calendar, removing from database",
      user_id: user.id,
      google_event_id: db_event.google_event_id
    }.to_json)

    db_event.destroy
  end

  # Detect which specific fields the user edited in Google Calendar
  # Returns an array of field names that differ from our DB state
  def detect_user_edited_fields(db_event, gcal_event)
    edited_fields = []

    # Extract data from Google Calendar event
    gcal_summary = gcal_event.summary
    gcal_location = gcal_event.location
    gcal_description = gcal_event.description

    # Parse Google Calendar times to Ruby Time objects in Eastern timezone
    gcal_start_time = parse_gcal_time(gcal_event.start)
    gcal_end_time = parse_gcal_time(gcal_event.end)

    # Compare each field with our local DB state
    edited_fields << "summary" if gcal_summary != db_event.summary
    edited_fields << "location" if gcal_location != db_event.location
    edited_fields << "description" if gcal_description.present? # Description is generated, any user value is an edit

    # Time comparison - handle nil cases properly
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

    if edited_fields.any?
      Rails.logger.info "User edit detected - Fields: #{edited_fields.join(', ')}"
    end

    edited_fields
  end

  # Check if user edited any field including recurrence
  # Note: recurrence edits are detected but not tracked in user_edited_fields
  # since recurrence is determined by the course schedule
  def user_edited_event?(db_event, gcal_event)
    return true if detect_user_edited_fields(db_event, gcal_event).any?

    # Also check recurrence (not tracked for field-level merging)
    gcal_recurrence = gcal_event.recurrence
    normalize_recurrence(gcal_recurrence) != normalize_recurrence(db_event.recurrence)
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

  def apply_preferences_to_event(syncable, course_event, preference_resolver: nil, template_renderer: nil)
    return course_event unless syncable

    # Use provided instances or create new ones (for backward compatibility)
    resolver = preference_resolver || PreferenceResolver.new(user)
    renderer = template_renderer || CalendarTemplateRenderer.new

    # Resolve preferences for this syncable (meeting_time, final_exam, or university_calendar_event)
    prefs = resolver.resolve_for(syncable)

    # Build template context based on syncable type
    context = case syncable
              when FinalExam
                CalendarTemplateRenderer.build_context_from_final_exam(syncable)
              when UniversityCalendarEvent
                CalendarTemplateRenderer.build_context_from_university_calendar_event(syncable)
              else
                CalendarTemplateRenderer.build_context_from_meeting_time(syncable)
              end

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
  # @param color_id_or_hex [Integer, String] Either a numeric ID (1-11) or hex code (WITCC or Google event)
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

    # If it's a hex code, try converting from WITCC hex first, then Google event hex
    if color_id_or_hex.is_a?(String) && color_id_or_hex.start_with?("#")
      normalized_hex = color_id_or_hex.downcase

      # Try WITCC hex to color ID conversion first (e.g., "#039be5" -> 7)
      witcc_color_id = GoogleColors.witcc_to_color_id(normalized_hex)
      return witcc_color_id if witcc_color_id.present?

      # Fall back to searching Google event hex colors directly (e.g., "#46d6db" -> 7)
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
    when "hours"
      (time_value * 60).to_i
    when "days"
      (time_value * 1440).to_i
    else
      time_value.to_i # default to minutes (includes "minutes" case)
    end
  end

end
