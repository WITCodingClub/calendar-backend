# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id             :bigint           not null, primary key
#  access_level   :integer          default("user"), not null
#  calendar_token :string
#  first_name     :string
#  last_name      :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_users_on_calendar_token  (calendar_token) UNIQUE
#
class User < ApplicationRecord
  has_subscriptions

  has_many :enrollments, dependent: :destroy
  has_many :courses, through: :enrollments
  has_many :magic_links, dependent: :destroy
  has_many :oauth_credentials, dependent: :destroy
  has_many :emails, dependent: :destroy

  # Class method to find or create a user by email
  def self.find_or_create_by_email(email_address)
    email_record = Email.find_by(email: email_address)

    if email_record
      email_record.user
    else
      # Create user and email in a transaction
      transaction do
        user = create!
        user.emails.create!(email: email_address, primary: true)
        user
      end
    end
  end

  # Class method to find a user by email
  def self.find_by_email(email_address)
    Email.find_by(email: email_address)&.user
  end

  enum :access_level, {
    user: 0,
    admin: 1,
    super_admin: 2,
    owner: 3
  }, default: :user, null: false

  # Convenience methods for accessing Google OAuth credentials
  def google_credential
    @google_credential ||= oauth_credentials.find_by(provider: "google")
  end

  def google_uid
    google_credential&.uid
  end

  def google_access_token
    google_credential&.access_token
  end

  def google_refresh_token
    google_credential&.refresh_token
  end

  def google_token_expires_at
    google_credential&.token_expires_at
  end

  def google_course_calendar_id
    google_credential&.course_calendar_id
  end

  def google_course_calendar_id=(value)
    return unless google_credential
    google_credential.course_calendar_id = value
    google_credential.save!
  end

  def admin_access?
    admin? || super_admin? || owner?
  end

  # Get the user's primary email address
  def email
    emails.find_by(primary: true)&.email
  end

  # Set the user's primary email address
  def email=(value)
    primary_email = emails.find_or_initialize_by(primary: true)
    primary_email.email = value
    primary_email.save! if persisted?
  end

  def full_name
    # first_name then last_name or John Doe if no name
    "#{first_name} #{last_name}"
  end

  def cal_url
    "#{Rails.application.routes.url_helpers.root_url}/calendar/#{calendar_token}.ics"
  end

  def generate_calendar_token
    if calendar_token.blank?
      self.calendar_token = SecureRandom.urlsafe_base64(32)
      save!
    end
  end

  def access_level_text
    case access_level
    when "user" then "User"
    when "admin" then "Admin"
    when "super_admin" then "Super Admin"
    when "owner" then "Owner"
    else "Unknown"
    end
  end

  def google_token_expired?
    google_credential&.token_expired? || false
  end

  def sync_course_schedule
    service = GoogleCalendarService.new(self)

    # Build events from enrollments - each course can have multiple meeting times
    events = []

    enrollments.includes(course: [meeting_times: [:room, :building]]).each do |enrollment|
      course = enrollment.course

      course.meeting_times.each do |meeting_time|
        # Skip if no meeting days are set
        next unless has_meeting_days?(meeting_time)

        # Find the first date this class actually meets
        first_meeting_date = find_first_meeting_date(meeting_time)
        next unless first_meeting_date

        # Convert integer times (e.g., 900 = 9:00 AM) to DateTime objects
        start_time = parse_time(first_meeting_date, meeting_time.begin_time)
        end_time = parse_time(first_meeting_date, meeting_time.end_time)
        next unless start_time && end_time

        # Build location string
        location = if meeting_time.room && meeting_time.building
          "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
        elsif meeting_time.room
          meeting_time.room.name
        end

        # Build course code from subject-number-section
        course_code = [course.subject, course.course_number, course.section_number].compact.join("-")

        # Build recurrence rule for weekly repeating events
        recurrence_rule = build_recurrence_rule(meeting_time)

        events << {
          summary: course.title,
          description: course_code,
          location: location,
          start_time: start_time,
          end_time: end_time,
          course_code: course_code,
          recurrence: recurrence_rule ? [recurrence_rule] : nil
        }
      end
    end

    service.update_calendar_events(events)
  end

  def has_meeting_days?(meeting_time)
    meeting_time.monday || meeting_time.tuesday || meeting_time.wednesday ||
    meeting_time.thursday || meeting_time.friday || meeting_time.saturday ||
    meeting_time.sunday
  end

  def find_first_meeting_date(meeting_time)
    # Map day booleans to wday numbers (0=Sunday, 1=Monday, etc.)
    meeting_wdays = []
    meeting_wdays << 0 if meeting_time.sunday
    meeting_wdays << 1 if meeting_time.monday
    meeting_wdays << 2 if meeting_time.tuesday
    meeting_wdays << 3 if meeting_time.wednesday
    meeting_wdays << 4 if meeting_time.thursday
    meeting_wdays << 5 if meeting_time.friday
    meeting_wdays << 6 if meeting_time.saturday

    return nil if meeting_wdays.empty?

    # Start from the meeting start_date
    current_date = meeting_time.start_date.to_date

    # Find the first day that matches one of the meeting days (max 7 days search)
    7.times do
      return current_date if meeting_wdays.include?(current_date.wday)
      current_date += 1.day
    end

    nil
  end

  def parse_time(date, time_int)
    return nil unless date && time_int

    # Convert integer time (e.g., 900 = 9:00 AM, 1330 = 1:30 PM)
    hours = time_int / 100
    minutes = time_int % 100

    Time.zone.local(date.year, date.month, date.day, hours, minutes)
  end

  def build_recurrence_rule(meeting_time)
    days = []
    days << "MO" if meeting_time.monday
    days << "TU" if meeting_time.tuesday
    days << "WE" if meeting_time.wednesday
    days << "TH" if meeting_time.thursday
    days << "FR" if meeting_time.friday
    days << "SA" if meeting_time.saturday
    days << "SU" if meeting_time.sunday

    return nil if days.empty?

    # Format: RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20240515T235959Z
    until_date = meeting_time.end_date.strftime('%Y%m%dT235959Z')
    "RRULE:FREQ=WEEKLY;BYDAY=#{days.join(',')};UNTIL=#{until_date}"
  end

  # Add a method to handle calendar deletion/cleanup
  def delete_course_calendar
    return unless google_course_calendar_id.present?

    service = GoogleCalendarService.new(self)
    service_account_service = service.send(:service_account_calendar_service)

    service_account_service.delete_calendar(google_course_calendar_id)
    self.google_course_calendar_id = nil
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to delete calendar: #{e.message}"
  end

  def create_or_get_course_calendar
    GoogleCalendarService.new(self).create_or_get_course_calendar
  end

  def refresh_google_token!
    require "googleauth"
    return unless google_credential

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: google_access_token,
      refresh_token: google_refresh_token,
      expires_at: google_token_expires_at
    )

    credentials.refresh!
    google_credential.update!(
      access_token: credentials.access_token,
      token_expires_at: Time.at(credentials.expires_at)
    )

    # Clear the cached credential
    @google_credential = nil
  end

  def flipper_id
    self.emails.find_by(primary: true)&.email
  end

  private

  def build_google_authorization
    require "googleauth"
    return unless google_credential

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: google_access_token,
      refresh_token: google_refresh_token,
      expires_at: google_token_expires_at
    )

    # Refresh the token if needed
    if google_token_expired?
      credentials.refresh!
      google_credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.at(credentials.expires_at)
      )
      # Clear the cached credential
      @google_credential = nil
    end

    credentials
  end

  def generate_calendar_token
    self.calendar_token ||= SecureRandom.urlsafe_base64(32)
    self.save!
  end

end
