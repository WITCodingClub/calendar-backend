# frozen_string_literal: true

class FriendshipMailer < ApplicationMailer
  def request_received(friendship)
    @friendship = friendship
    @requester  = friendship.requester
    @addressee  = friendship.addressee
    @requests_url = requests_dashboard_friends_url

    mail(
      to: @addressee.email,
      subject: "#{@requester.full_name} sent you a friend request on WIT Calendar"
    )
  end
end
