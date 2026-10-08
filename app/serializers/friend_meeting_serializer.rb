# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meetings
#
#  id              :bigint           not null, primary key
#  cancelled_at    :datetime
#  end_time        :datetime         not null
#  frequency       :string           default("one_time"), not null
#  idempotency_key :string
#  invite_friends  :boolean          default(FALSE), not null
#  location        :string
#  repeat_until    :date
#  start_time      :datetime         not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_friend_meetings_unique_idempotency_key  (user_id,idempotency_key) UNIQUE WHERE (idempotency_key IS NOT NULL)
#  index_friend_meetings_on_term_id            (term_id)
#  index_friend_meetings_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
# One meeting as `viewer` sees it, for the create, show, update, and list
# routes. The owner also sees where the meeting goes and the status of each
# place. An invited friend sees only the meeting, because the places are the
# owner's own calendars.
#
# Times are in the meeting's local zone. `start_time` and `end_time` are the
# first occurrence; GET /api/friends/meetings lists each occurrence.
class FriendMeetingSerializer
  def initialize(meeting, viewer:)
    @meeting = meeting
    @viewer  = viewer
  end

  def as_json(*)
    owner = @meeting.owned_by?(@viewer)

    {
      id:             @meeting.public_id,
      title:          @meeting.title,
      location:       @meeting.location,
      start_time:     local(@meeting.start_time),
      end_time:       local(@meeting.end_time),
      time_zone:      FriendMeeting::LOCAL_TIME_ZONE,
      frequency:      @meeting.frequency,
      recurrence:     @meeting.recurrence&.first,
      repeat_until:   @meeting.repeat_until&.iso8601,
      invite_friends: @meeting.invite_friends,
      role:           owner ? "owner" : "invitee",
      can_edit:       owner,
      can_delete:     owner,
      can_leave:      !owner,
      owner:          person(@meeting.user),
      friends:        @meeting.attendees.map { |friend| person(friend) },
      destinations:   owner ? @meeting.destinations : [],
      publications:   owner ? publications : []
    }
  end

  private

  def publications
    @meeting.publications.sort_by(&:id).map do |publication|
      {
        provider:          publication.provider,
        status:            publication.status,
        invitation_status: publication.invitation_status
      }
    end
  end

  def person(user) = { id: user.public_id, name: user.full_name }

  def local(time) = time.in_time_zone(FriendMeeting::LOCAL_TIME_ZONE).iso8601
end
