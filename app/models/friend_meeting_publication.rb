# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meeting_publications
#
#  id                  :bigint           not null, primary key
#  invitations_sent_at :datetime
#  last_error          :string
#  provider            :string           not null
#  sends_invitations   :boolean          default(FALSE), not null
#  status              :string           default("queued"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  friend_meeting_id   :bigint           not null
#
# Indexes
#
#  idx_friend_meeting_publications_unique  (friend_meeting_id,provider) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (friend_meeting_id => friend_meetings.id)
#
# One place that a FriendMeeting goes to: a provider course calendar or the
# ICS feed. The person picks the places when they make the meeting.
#
# `status` says where the provider event is: `queued` until a job writes it,
# `published` after, and `failed` when the last try failed. The ICS feed reads
# the database, so its row is `published` at once.
#
# At most one provider row has `sends_invitations`. `invitations_sent_at`
# records that the provider sent them, so the app never sends them again, for
# example when it puts back an event that went missing.
class FriendMeetingPublication < ApplicationRecord
  PROVIDERS = { google: "google", microsoft: "microsoft", ics: "ics" }.freeze
  # The providers whose events the app writes. The ICS feed has no event.
  CALENDAR_PROVIDERS = %w[google microsoft].freeze
  STATUSES = { queued: "queued", published: "published", failed: "failed" }.freeze

  enum :provider, PROVIDERS, validate: true, prefix: true
  enum :status, STATUSES, validate: true

  belongs_to :friend_meeting

  validates :provider, uniqueness: { scope: :friend_meeting_id }

  scope :calendars, -> { where(provider: CALENDAR_PROVIDERS) }

  def calendar? = CALENDAR_PROVIDERS.include?(provider)

  # `not_requested` when this place does not send the invitations. Else
  # `sent`, `failed` (the last try failed before they went out), or `queued`.
  def invitation_status
    return "not_requested" unless sends_invitations?
    return "sent" if invitations_sent_at

    failed? ? "failed" : "queued"
  end

  def mark_published!(invitations_sent: false)
    attributes = { status: "published", last_error: nil }
    attributes[:invitations_sent_at] = Time.current if invitations_sent
    update!(attributes)
  end

  def mark_failed!(error)
    update!(status: "failed", last_error: error.to_s.truncate(255))
  end
end
