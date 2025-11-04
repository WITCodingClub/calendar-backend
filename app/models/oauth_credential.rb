# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_credentials
# Database name: primary
#
#  id               :bigint           not null, primary key
#  access_token     :string           not null
#  email            :string
#  metadata         :jsonb
#  provider         :string           not null
#  refresh_token    :string
#  token_expires_at :datetime
#  uid              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_oauth_credentials_on_provider_and_uid     (provider,uid) UNIQUE
#  index_oauth_credentials_on_user_id              (user_id)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class OauthCredential < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true, inclusion: { in: %w[google] }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :access_token, presence: true
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must be a valid email address" }

  encrypts :access_token
  encrypts :refresh_token

  # Convenience methods for metadata access
  def course_calendar_id
    metadata&.dig("course_calendar_id")
  end

  def course_calendar_id=(value)
    self.metadata ||= {}
    self.metadata["course_calendar_id"] = value
  end

  # Check if token is expired or about to expire (within 5 minutes)
  def token_expired?
    token_expires_at.nil? || token_expires_at <= 5.minutes.from_now
  end

  # Scope for finding credentials by provider
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :google, -> { for_provider("google") }

end
