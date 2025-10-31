# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  access_level              :integer          default("user"), not null
#  calendar_token            :string
#  email                     :string           default(""), not null
#  first_name                :string
#  google_access_token       :string
#  google_refresh_token      :string
#  google_token_expires_at   :datetime
#  google_uid                :string
#  last_name                 :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  google_course_calendar_id :string
#
# Indexes
#
#  index_users_on_calendar_token  (calendar_token) UNIQUE
#  index_users_on_email           (email) UNIQUE
#  index_users_on_google_uid      (google_uid)
#
class User < ApplicationRecord
  has_subscriptions

  has_many :enrollments, dependent: :destroy
  has_many :courses, through: :enrollments
  has_many :magic_links, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: {
    with: /@wit\.edu\z/i,
    message: "must be a @wit.edu email address"
  }

  enum :access_level, {
    user: 0,
    admin: 1,
    super_admin: 2,
    owner: 3
  }, default: :user, null: false

  def admin_access?
    admin? || super_admin? || owner?
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
    google_token_expires_at.present? && Time.current >= google_token_expires_at
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

  private

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
    update!(google_course_calendar_id: nil)
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to delete calendar: #{e.message}"
  end

  def create_or_get_course_calendar
    GoogleCalendarService.new(self).create_or_get_course_calendar
  end

  def refresh_google_token!
    require "googleauth"

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: google_access_token,
      refresh_token: google_refresh_token,
      expires_at: google_token_expires_at
    )

    credentials.refresh!
    update!(
      google_access_token: credentials.access_token,
      google_token_expires_at: Time.at(credentials.expires_at)
    )
  end

  private

  def build_google_authorization
    require "googleauth"

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
      update!(
        google_access_token: credentials.access_token,
        google_token_expires_at: Time.at(credentials.expires_at)
      )
    end

    credentials
  end

end
