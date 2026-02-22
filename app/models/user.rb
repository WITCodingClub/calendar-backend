# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default("user"), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  first_name                   :string
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  notifications_disabled_until :datetime
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#
class User < ApplicationRecord
  include GoogleOauthable
  include CourseScheduleSyncable
  include CalendarTokenable
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :usr

  # Use hashid for URLs instead of regular ID (without usr_ prefix)
  def to_param
    hashid
  end

  has_subscriptions

  has_many :enrollments, dependent: :destroy
  has_many :courses, through: :enrollments
  has_many :oauth_credentials, dependent: :destroy
  has_many :emails, dependent: :destroy
  has_many :google_calendars, through: :oauth_credentials
  has_many :google_calendar_events, through: :google_calendars
  has_many :calendar_preferences, dependent: :destroy
  has_many :event_preferences, dependent: :destroy
  has_one :user_extension_config, dependent: :destroy
  has_many :security_events, dependent: :destroy
  has_many :requirement_completions, dependent: :destroy
  before_create :generate_calendar_token
  after_create :create_user_extension_config

  # Class method to find or create a user by email
  def self.find_or_create_by_email(email_address, fname, lname)
    email_record = Email.find_by(email: email_address)

    if email_record
      email_record.user
    else
      # Create user and email in a transaction
      transaction do
        user = create!(first_name: fname, last_name: lname)
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

  scope :users, -> { where(access_level: [:user, :admin, :super_admin, :owner]) }
  scope :admins, -> { where(access_level: [:admin, :super_admin, :owner]) }
  scope :super_admins, -> { where(access_level: [:super_admin, :owner]) }
  scope :owners, -> { where(access_level: :owner) }

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

  def access_level_text
    case access_level
    when "user" then "User"
    when "admin" then "Admin"
    when "super_admin" then "Super Admin"
    when "owner" then "Owner"
    else "Unknown"
    end
  end

  def flipper_id
    self.emails.find_by(primary: true)&.email
  end

  # Check if notifications are currently disabled (DND mode)
  def notifications_disabled?
    notifications_disabled_until.present? && notifications_disabled_until > Time.current
  end

  # Disable notifications (enable DND mode) until the specified time
  # Pass nil for duration to disable indefinitely
  def disable_notifications!(duration: nil)
    if duration.nil?
      # Indefinite - set to a far future date
      update!(notifications_disabled_until: 100.years.from_now)
    else
      update!(notifications_disabled_until: duration.from_now)
    end
  end

  # Re-enable notifications (disable DND mode)
  def enable_notifications!
    update!(notifications_disabled_until: nil)
  end

  private

  def create_user_extension_config
    UserExtensionConfig.create(user: self)
  end

end
