# frozen_string_literal: true

# The BusyBlocks of each person in a friend group, for
# GET /api/friends/groups/:group_id/busy_blocks. Each person has the same
# "busy" list that BusyBlocksSerializer gives for one friend.
class FriendGroupBusyBlocksSerializer
  # blocks_by_person: { user => [BusyBlocks::Block] }, owner first.
  def initialize(group, blocks_by_person, from:, to:)
    @group            = group
    @blocks_by_person = blocks_by_person
    @from             = from
    @to               = to
  end

  def as_json(*)
    {
      group_id:   @group.public_id,
      time_zone:  Time.zone.tzinfo.name,
      start_date: @from.iso8601,
      end_date:   @to.iso8601,
      people:     @blocks_by_person.map { |person, blocks| person_json(person, blocks) }
    }
  end

  private

  def person_json(person, blocks)
    busy = BusyBlocksSerializer.new(blocks, from: @from, to: @to).as_json[:busy]

    FriendSerializer.new(person).as_json.merge(role: person.id == @group.user_id ? "owner" : "member", busy: busy)
  end
end
