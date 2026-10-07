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
# The meeting link that the API and the dashboard show to its owner.
#
# `url` holds the raw token, so pass it only in the answer to the request that
# made the link. The app stores only a digest, so a later list cannot show it.
# `booking` holds the time and the guest after a guest picks a time.
class MeetingLinkSerializer
  def initialize(link, url: nil)
    @link = link
    @url  = url
  end

  def as_json(*)
    json = {
      id:               @link.public_id,
      title:            @link.title,
      starts_on:        @link.starts_on.iso8601,
      ends_on:          @link.ends_on.iso8601,
      duration_minutes: @link.duration_minutes,
      expires_at:       @link.expires_at.iso8601,
      status:           @link.status,
      created_at:       @link.created_at.iso8601,
      booking:          booking_json
    }
    @url ? json.merge(url: @url) : json
  end

  def self.render_collection(links)
    links.map { |link| new(link).as_json }
  end

  private

  def booking_json
    meeting = @link.friend_meeting
    return nil unless meeting

    {
      meeting_id:  meeting.public_id,
      start_time:  meeting.start_time.iso8601,
      end_time:    meeting.end_time.iso8601,
      guest_name:  meeting.guest_name,
      guest_email: meeting.guest_email
    }
  end
end
