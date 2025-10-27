# == Schema Information
#
# Table name: magic_links
# Database name: primary
#
#  id         :bigint           not null, primary key
#  expires_at :datetime         not null
#  token      :string           not null
#  used_at    :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_magic_links_on_token    (token) UNIQUE
#  index_magic_links_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class MagicLink < ApplicationRecord
  belongs_to :user

  before_validation :generate_token, :set_expiration, on: :create

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :valid_links, -> { where("expires_at > ? AND used_at IS NULL", Time.current) }

  def expired?
    Time.current > expires_at
  end

  def used?
    used_at.present?
  end

  def usable?
    !expired? && !used?
  end

  def mark_as_used!
    update!(used_at: Time.current)
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def set_expiration
    self.expires_at = 15.minutes.from_now
  end
end
