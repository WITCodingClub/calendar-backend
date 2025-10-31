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

  before_create :generate_calendar_token

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

    # Build events from enrollments
    events = enrollments.includes(:course).map do |enrollment|
      course = enrollment.course
      {
        summary: course.name,
        description: "#{course.code} - #{course.instructor}",
        location: course.location,
        start_time: course.start_time,
        end_time: course.end_time,
        course_code: course.code,
        # Add recurrence rules if needed
      }
    end

    service.update_calendar_events(events)
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

  def generate_calendar_token
    self.calendar_token ||= SecureRandom.urlsafe_base64(32)
  end

end
