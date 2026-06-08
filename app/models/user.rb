# frozen_string_literal: true

class User < ApplicationRecord
  include GoogleOauthable
  include CourseScheduleSyncable
  include CalendarTokenable
  include EncodedIds::HashidIdentifiable

  devise :database_authenticatable, :registerable,
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
