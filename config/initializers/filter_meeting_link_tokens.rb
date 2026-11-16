# frozen_string_literal: true

# A meeting link token is in the URL path (/meet/<token>), and anyone with the
# token can book the owner's time. `filter_parameters` hides it in the logged
# parameters, but not in the path. Rails logs the path from
# ActionDispatch::Request#filtered_path ("Started GET ..."), so this replaces
# the token there with [FILTERED]. PATH_INFO does not change, so routing does
# not change.
require Rails.root.join("app/lib/request_paths")

module FilterMeetingLinkTokens
  MEETING_LINK_PATH = %r{\A#{RequestPaths::MEETING_LINK_PREFIX}[^/?]+}

  def filtered_path
    @filtered_meeting_link_path ||= super.sub(MEETING_LINK_PATH, "#{RequestPaths::MEETING_LINK_PREFIX}[FILTERED]")
  end
end

ActionDispatch::Request.prepend(FilterMeetingLinkTokens)

# "Redirected to .../meet/<token>" after a booking or a sign-in.
Rails.application.config.filter_redirect << /#{RequestPaths::MEETING_LINK_PREFIX}/o
