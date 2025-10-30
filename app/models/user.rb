# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id           :bigint           not null, primary key
#  access_level :integer          default("user"), not null
#  email        :string           default(""), not null
#  first_name   :string
#  last_name    :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_users_on_email  (email) UNIQUE
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

  private

  def generate_calendar_token
    self.calendar_token ||= SecureRandom.urlsafe_base64(32)
  end

end
