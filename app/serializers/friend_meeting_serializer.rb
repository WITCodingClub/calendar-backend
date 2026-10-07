# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meetings
#
#  id             :bigint           not null, primary key
#  end_time       :datetime         not null
#  frequency      :string           default("one_time"), not null
#  guest_email    :string
#  guest_name     :string
#  invite_friends :boolean          default(FALSE), not null
#  location       :string
#  repeat_until   :date
#  start_time     :datetime         not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  index_friend_meetings_on_term_id  (term_id)
#  index_friend_meetings_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
# The answer to POST /api/friends/meetings. `calendar_providers` lists the
# provider calendars that get the meeting from a background job. The ICS feed
# shows the meeting at once, so it is not in the list.
class FriendMeetingSerializer
  def initialize(meeting, calendar_providers: [])
    @meeting            = meeting
    @calendar_providers = calendar_providers
  end

  def as_json(*)
    {
      id:                 @meeting.public_id,
      title:              @meeting.title,
      location:           @meeting.location,
      start_time:         @meeting.start_time.iso8601,
      end_time:           @meeting.end_time.iso8601,
      frequency:          @meeting.frequency,
      repeat_until:       @meeting.repeat_until&.iso8601,
      invite_friends:     @meeting.invite_friends,
      friends:            @meeting.attendees.map { |friend| { id: friend.public_id, name: friend.full_name } },
      calendar_providers: @calendar_providers
    }
  end
end
