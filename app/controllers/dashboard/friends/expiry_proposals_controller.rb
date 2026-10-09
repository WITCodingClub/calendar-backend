# frozen_string_literal: true

module Dashboard
  module Friends
    # An open proposal for a new end date. update accepts the friend's
    # proposal. destroy declines it, or withdraws your own.
    #
    # Both actions work with the friend_expiry flag off. The proposal email
    # links to the page that shows the proposal, and the proposer had the flag.
    class ExpiryProposalsController < Dashboard::ApplicationController
      include Dashboard::FriendFeatures

      # PATCH /dashboard/friends/:friend_id/expiry_proposal
      def update
        friend, friendship = find_expiry_friendship(require_flag: false)
        return if performed?

        authorize friendship, :accept_expiry?
        friendship.accept_expiry_proposal!(by: current_user)

        notice = if friendship.temporary?
          "Your friendship with #{friend.first_name} now ends on #{friendship.expires_at.to_date.to_fs(:long)}."
        else
          "#{friend.first_name} is now a permanent friend."
        end
        redirect_to dashboard_friends_path, notice: notice
      end

      # DELETE /dashboard/friends/:friend_id/expiry_proposal
      def destroy
        _friend, friendship = find_expiry_friendship(require_flag: false)
        return if performed?

        authorize friendship, :decline_expiry?
        friendship.decline_expiry_proposal!(by: current_user)

        redirect_to dashboard_friends_path, notice: "The proposal is closed. The end date did not change."
      end
    end
  end
end
