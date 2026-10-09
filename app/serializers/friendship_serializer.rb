# frozen_string_literal: true

# Serializes a friendship from the point of view of one of its two users.
#
#   FriendshipSerializer.new(friendship, viewer).as_json          # the friendship
#   FriendshipSerializer.new(friendship, viewer).as_request       # GET /api/friends/requests
#   FriendshipSerializer.new(friendship, viewer).expiry_json      # expiry keys in GET /api/friends
#
# expires_at is an ISO 8601 time, or nil for a permanent friendship.
# expiry_proposal is nil, or the later end date one user proposed:
#
#   { expires_at: "...", permanent: false, proposed_by: "usr_...", can_accept: true,
#     review_url: "https://.../dashboard/friends" }
#
# The API cannot answer a proposal (#719). review_url is the dashboard page
# where the other user accepts or declines it, and the proposer withdraws it.
# == Schema Information
#
# Table name: friendships
#
#  id                   :bigint           not null, primary key
#  addressee_visibility :integer          default(0), not null
#  expires_at           :datetime
#  proposed_expires_at  :datetime
#  proposed_permanent   :boolean          default(FALSE), not null
#  requester_visibility :integer          default(0), not null
#  status               :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  addressee_id         :bigint           not null
#  proposed_by_id       :bigint
#  requester_id         :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_expires_at                     (expires_at) WHERE (expires_at IS NOT NULL)
#  index_friendships_on_proposed_by_id                 (proposed_by_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#  index_friendships_on_unordered_pair                 (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (proposed_by_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
class FriendshipSerializer
  def self.render_requests(friendships, viewer)
    friendships.map { |f| new(f, viewer).as_request }
  end

  def initialize(friendship, viewer)
    @friendship = friendship
    @viewer     = viewer
  end

  def as_json(*)
    {
      friendship_id:   @friendship.public_id,
      status:          @friendship.status,
      expires_at:      expires_at,
      expiry_proposal: expiry_proposal,
      friend:          user_json(friend)
    }
  end

  # The expiry keys of one friend in GET /api/friends.
  def expiry_json
    { expires_at: expires_at, expiry_proposal: expiry_proposal }
  end

  def as_request
    key = @friendship.requester?(@viewer) ? :to : :from

    {
      :request_id      => @friendship.public_id,
      key              => user_json(friend),
      :created_at      => @friendship.created_at.iso8601,
      :expires_at      => expires_at,
      :expiry_proposal => expiry_proposal
    }
  end

  private

  def friend = @friendship.friend_for(@viewer)

  def expires_at = @friendship.expires_at&.iso8601

  # No query: the proposer is always the viewer or the friend.
  def expiry_proposal
    return nil unless @friendship.expiry_proposal?

    proposed_by_viewer = @friendship.proposed_by_id == @viewer.id

    {
      expires_at:  @friendship.proposed_expires_at&.iso8601,
      permanent:   @friendship.proposed_permanent?,
      proposed_by: (proposed_by_viewer ? @viewer : friend).public_id,
      can_accept:  !proposed_by_viewer,
      review_url:  review_url
    }
  end

  # A pending request shows on the requests page, a friend on the friends page.
  def review_url
    helpers = Rails.application.routes.url_helpers
    options = Rails.application.config.action_controller.default_url_options || {}

    @friendship.pending? ? helpers.dashboard_friends_requests_url(**options) : helpers.dashboard_friends_url(**options)
  end

  def user_json(user)
    { id: user.public_id, name: user.full_name }
  end
end
