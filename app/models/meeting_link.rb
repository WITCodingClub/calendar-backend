# frozen_string_literal: true

# == Schema Information
#
# Table name: meeting_links
#
#  id                :bigint           not null, primary key
#  duration_minutes  :integer          not null
#  ends_on           :date             not null
#  expires_at        :datetime         not null
#  revoked_at        :datetime
#  starts_on         :date             not null
#  title             :string
#  token_digest      :string           not null
#  used_at           :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  friend_meeting_id :bigint
#  guest_user_id     :bigint
#  user_id           :bigint           not null
#
# Indexes
#
#  index_meeting_links_on_friend_meeting_id  (friend_meeting_id)
#  index_meeting_links_on_guest_user_id      (guest_user_id)
#  index_meeting_links_on_token_digest       (token_digest) UNIQUE
#  index_meeting_links_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (friend_meeting_id => friend_meetings.id) ON DELETE => nullify
#  fk_rails_...  (guest_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
# A one-time meeting link (#652). The owner shares it with a person who is not
# a friend, for example a professor or a project partner from another class.
# That person picks one free time, and the link is used up.
#
# The token is random and is shown once, when the link is made. Only its
# SHA-256 digest is stored, like a password reset token.
class MeetingLink < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :mlk, min_hash_length: 12

  DURATIONS        = [ 15, 30, 45, 60, 90, 120 ].freeze
  MAX_RANGE_DAYS   = 30
  MAX_EXPIRY       = 60.days
  MAX_ACTIVE_LINKS = 20
  TITLE_MAX_LENGTH = FriendMeeting::TITLE_MAX_LENGTH

  STATUSES = %w[active used revoked expired].freeze

  belongs_to :user
  belongs_to :friend_meeting, optional: true
  belongs_to :guest_user, class_name: "User", optional: true

  # The raw token, only on the instance that made it. It is never stored.
  attr_reader :token

  validates :starts_on, :ends_on, :expires_at, presence: true
  validates :duration_minutes, inclusion: { in: DURATIONS }
  validates :title, length: { maximum: TITLE_MAX_LENGTH }
  validates :token_digest, presence: true, uniqueness: true
  validate :range_is_valid, on: :create
  validate :expiry_is_valid, on: :create
  validate :active_link_limit, on: :create

  before_validation :generate_token, :default_expiry, on: :create

  scope :usable, -> { where(used_at: nil, revoked_at: nil).where(expires_at: Time.current..) }
  scope :newest_first, -> { order(created_at: :desc) }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  # Returns the link for a raw token, or nil. A token that is not usable any
  # more finds the link too, so the caller can tell its own guest apart.
  def self.find_by_token(token)
    return nil if token.blank?

    find_by(token_digest: digest(token))
  end

  def usable?
    used_at.nil? && revoked_at.nil? && expires_at > Time.current
  end

  def used?    = used_at.present?
  def revoked? = revoked_at.present?

  def status
    if used? then "used"
    elsif revoked? then "revoked"
    elsif expires_at <= Time.current then "expired"
    else "active"
    end
  end

  def duration = duration_minutes.minutes

  # The link to share. Only the instance that made the link knows the token,
  # so this is nil on a link read back from the database.
  def url
    return nil if token.blank?

    url_options = Rails.application.config.action_controller.default_url_options || {}
    Rails.application.routes.url_helpers.meeting_link_url(token, **url_options)
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  # The event title. The owner's title, or one that names the guest.
  def meeting_title(guest_name)
    title.presence || "Meeting with #{guest_name}"
  end

  private

  def generate_token
    return if token_digest.present?

    @token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@token)
  end

  # With no expiry, the link works until the end of its last day.
  def default_expiry
    self.expires_at ||= ends_on&.in_time_zone&.end_of_day
  end

  def range_is_valid
    return if starts_on.blank? || ends_on.blank?

    if starts_on < Time.zone.today
      errors.add(:starts_on, "must be today or later")
    elsif ends_on < starts_on
      errors.add(:ends_on, "must be on or after the start date")
    elsif (ends_on - starts_on).to_i + 1 > MAX_RANGE_DAYS
      errors.add(:ends_on, "must be no more than #{MAX_RANGE_DAYS} days after the start date")
    end
  end

  def expiry_is_valid
    return if expires_at.blank?

    if expires_at <= Time.current
      errors.add(:expires_at, "must be in the future")
    elsif expires_at > MAX_EXPIRY.from_now
      errors.add(:expires_at, "must be no more than #{MAX_EXPIRY.in_days.to_i} days from now")
    end
  end

  def active_link_limit
    return if user.nil?
    return if user.meeting_links.usable.count < MAX_ACTIVE_LINKS

    errors.add(:base, "You can have no more than #{MAX_ACTIVE_LINKS} active meeting links. Revoke one first.")
  end
end
