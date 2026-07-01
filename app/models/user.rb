# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default("user"), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  confirmation_sent_at         :datetime
#  confirmation_token           :string
#  confirmed_at                 :datetime
#  current_sign_in_at           :datetime
#  current_sign_in_ip           :string
#  email                        :string           default(""), not null
#  encrypted_password           :string           default(""), not null
#  failed_attempts              :integer          default(0), not null
#  first_name                   :string
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  last_sign_in_at              :datetime
#  last_sign_in_ip              :string
#  locked_at                    :datetime
#  notifications_disabled_until :datetime
#  remember_created_at          :datetime
#  reset_password_sent_at       :datetime
#  reset_password_token         :string
#  sign_in_count                :integer          default(0), not null
#  unconfirmed_email            :string
#  unlock_token                 :string
#  wit_email                    :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_access_level           (access_level)
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_confirmation_token     (confirmation_token) UNIQUE
#  index_users_on_email                  (email) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#  index_users_on_reset_password_token   (reset_password_token) UNIQUE
#  index_users_on_wit_email              (wit_email)
#
class User < ApplicationRecord
  include GoogleOauthable
  include CourseScheduleSyncable
  include CalendarTokenable
  include EncodedIds::HashidIdentifiable

  # No :registerable — accounts are provisioned only via Google OAuth
  # (see AuthController#handle_user_login, which enforces the @wit.edu gate).
  # Self-service password signup would bypass that domain restriction.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable, :confirmable, :trackable, :timeoutable, :lockable

  set_public_id_prefix :usr

  def to_param
    hashid
  end

  has_many :enrollments, dependent: :destroy
  has_many :courses, through: :enrollments
  has_many :oauth_credentials, dependent: :destroy
  has_many :google_calendars, through: :oauth_credentials
  has_many :google_calendar_events, through: :google_calendars
  has_many :calendar_preferences, dependent: :destroy
  has_many :event_preferences, dependent: :destroy
  has_one :user_extension_config, dependent: :destroy
  has_many :security_events, dependent: :destroy

  has_many :sent_friendships, class_name: "Friendship", foreign_key: :requester_id,
           dependent: :destroy, inverse_of: :requester
  has_many :received_friendships, class_name: "Friendship", foreign_key: :addressee_id,
           dependent: :destroy, inverse_of: :addressee

  before_create :generate_calendar_token
  after_create :create_user_extension_config

  enum :access_level, {
    user: 0,
    admin: 1,
    super_admin: 2,
    owner: 3
  }, default: :user, null: false

  scope :admins, -> { where(access_level: [ :admin, :super_admin, :owner ]) }
  scope :super_admins, -> { where(access_level: [ :super_admin, :owner ]) }
  scope :owners, -> { where(access_level: :owner) }
  scope :needs_sync, -> { where(calendar_needs_sync: true) }

  def admin_access?
    admin? || super_admin? || owner?
  end

  def access_level_text
    access_level.to_s.humanize
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence || email
  end

  def notifications_disabled?
    notifications_disabled_until.present? && notifications_disabled_until > Time.current
  end

  def disable_notifications!(duration: nil)
    update!(notifications_disabled_until: duration.nil? ? 100.years.from_now : duration.from_now)
  end

  def enable_notifications!
    update!(notifications_disabled_until: nil)
  end

  def friends
    friend_ids = Friendship.accepted
                           .involving(self)
                           .pluck(:requester_id, :addressee_id)
                           .flatten
                           .uniq
                           .reject { |fid| fid == id }
    User.where(id: friend_ids)
  end

  def friend_of?(other_user)
    return false if other_user.nil? || other_user.id == id

    Friendship.accepted.exists?(
      "(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
      id, other_user.id, other_user.id, id
    )
  end

  def incoming_friend_requests
    Friendship.pending_for(self)
  end

  def outgoing_friend_requests
    Friendship.outgoing_from(self)
  end

  private

  def create_user_extension_config
    UserExtensionConfig.create(user: self)
  end
end
