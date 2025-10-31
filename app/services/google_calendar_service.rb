class GoogleCalendarService
  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def create_or_get_course_calendar
    return user.google_course_calendar_id if user.google_course_calendar_id.present?

    # Create calendar using service account
    calendar = create_calendar_with_service_account

    # Share with user
    share_calendar_with_user(calendar.id)

    # Add to user's calendar list
    add_calendar_to_user_list(calendar.id)

    # Save the calendar ID
    user.update!(google_course_calendar_id: calendar.id)

    calendar.id
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to create Google Calendar: #{e.message}"
    raise "Failed to create course calendar: #{e.message}"
  end

  def update_calendar_events(events)
    service = service_account_calendar_service
    calendar_id = user.google_course_calendar_id

    # Clear existing events (optional)
    clear_calendar_events(service, calendar_id)

    # Add new events with colors
    events.each do |event|
      add_event_to_calendar(service, calendar_id, event)
    end
  end

  def list_calendars
    service = service_account_calendar_service
    service.list_calendar_lists
  end

  def delete_calendar(calendar_id)
    service = service_account_calendar_service
    service.delete_calendar(calendar_id)
  end

  private

  def service_account_calendar_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = service_account_credentials
    service
  end

  def service_account_credentials
    # Check if OAuth refresh token is configured (preferred method)
    oauth_refresh_token = Rails.application.credentials.dig(:google, :service_account_oauth_refresh_token)

    if oauth_refresh_token.present?
      return service_account_oauth_credentials(oauth_refresh_token)
    end

    # Fallback to service account JSON key
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

  def service_account_oauth_credentials(refresh_token)
    # Use OAuth user credentials for the service account email
    # This provides user-level permissions instead of service account permissions
    Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR,
      refresh_token: refresh_token
    )
  end

  def user_calendar_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = user_google_authorization
    service
  end

  def user_google_authorization
    raise "User has no Google access token" if user.google_access_token.blank?
    raise "Google token has expired" if user.google_token_expired?

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: user.google_access_token,
      refresh_token: user.google_refresh_token,
      expires_at: user.google_token_expires_at
    )

    # Refresh the token if needed
    if user.google_token_expired?
      credentials.refresh!
      user.update!(
        google_access_token: credentials.access_token,
        google_token_expires_at: Time.at(credentials.expires_at)
      )
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

    # Give user writer access (can add/edit events but not delete calendar)
    rule = Google::Apis::CalendarV3::AclRule.new(
      scope: {
        type: 'user',
        value: user.email
      },
      role: 'reader'  # or 'writer' if you only want write access
    )

    # Insert ACL with send_notifications set to false to avoid the ugly email
    service.insert_acl(
      calendar_id,
      rule,
      send_notifications: false  # Don't send the default invite
    )

  rescue Google::Apis::ClientError => e
    # Ignore if user already has access
    raise unless e.status_code == 409
  end

  def add_calendar_to_user_list(calendar_id)
    service = user_calendar_service

    calendar_list_entry = Google::Apis::CalendarV3::CalendarListEntry.new(
      id: calendar_id,
      summary_override: "WIT Courses",  # Optional: customize how it appears for the user
      color_id: "9",  # Optional: set a default color (1-24)
      selected: true,  # Show by default in their calendar
      hidden: false
    )

    service.insert_calendar_list(calendar_list_entry)
  rescue Google::Apis::ClientError => e
    # Ignore if already in list
    raise unless e.status_code == 409
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

  def add_event_to_calendar(service, calendar_id, course_event)
    event = Google::Apis::CalendarV3::Event.new(
      summary: course_event[:summary],
      location: course_event[:location],
      description: course_event[:description],
      start: {
        date_time: course_event[:start_time].iso8601,
        time_zone: 'America/New_York'
      },
      end: {
        date_time: course_event[:end_time].iso8601,
        time_zone: 'America/New_York'
      },
      color_id: course_event[:color_id] || get_color_for_course(course_event[:course_code]),
      recurrence: course_event[:recurrence], # If you have recurring events
      guests_can_see_other_guests: false,
    )

    service.insert_event(calendar_id, event)
  end

  def get_color_for_course(course_code)
    # Map courses to Google Calendar colors (1-11)
    # You could hash the course code to get consistent colors
    colors = %w[1 2 3 4 5 6 7 8 9 10 11]
    colors[course_code.hash % colors.length]
  end
end