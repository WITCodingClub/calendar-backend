# frozen_string_literal: true

module Dashboard
  class ApplicationController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :require_processed_courses
    after_action  :verify_authorized

    private

    # Most dashboard pages are empty until the extension processes the user's
    # courses (#644). Send those users to the onboarding page. Account pages
    # skip this check, so a user can still manage or remove the account.
    def require_processed_courses
      return if onboarding_complete?

      # Keep a notice or alert from the previous redirect (for example the
      # sign-in "Welcome" notice), so the onboarding page shows it.
      flash.keep
      redirect_to dashboard_onboarding_path
    end

    def onboarding_complete?
      current_user.admin_access? || current_user.processed_courses?
    end

    # Where to go after a user answers a friend request. The friends page is
    # gated for a user with no processed courses, so send that user back to the
    # requests page instead.
    def friend_requests_return_path
      onboarding_complete? ? dashboard_friends_path : requests_dashboard_friends_path
    end
  end
end
