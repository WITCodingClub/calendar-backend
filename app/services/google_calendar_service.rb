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

  def get_available_colors
    service = service_account_calendar_service
    colors = service.get_color

    puts "\n=== Google Calendar Event Colors ==="
    colors.event.each do |id, color_info|
      puts "ID: #{id.rjust(2)} - Background: #{color_info.background} - Foreground: #{color_info.foreground}"
    end

    puts "\n=== Google Calendar Colors ==="
    colors.calendar.each do |id, color_info|
      puts "ID: #{id.rjust(2)} - Background: #{color_info.background} - Foreground: #{color_info.foreground}"
    end

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
      start: {
        date_time: course_event[:start_time].iso8601,
        time_zone: 'America/New_York'
      },
      end: {
        date_time: course_event[:end_time].iso8601,
        time_zone: 'America/New_York'
      },
      color_id: get_color_for_course(course_event[:course_code]),
      recurrence: course_event[:recurrence], # If you have recurring events
    )

    service.insert_event(calendar_id, event)
  end

  def get_color_for_course(course_code)
    # find the meeting time for the course as meeting_time has a event_color method
    meeting_time = MeetingTime.joins(:course).find_by(courses: { course_code: course_code })
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