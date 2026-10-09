# frozen_string_literal: true

module Dashboard
  class SettingsController < Dashboard::ApplicationController
    # An account page. It works before the user processes any courses.
    skip_before_action :require_processed_courses

    def show
      authorize current_user, :show?

      @sign_in_identities = current_user.sign_in_identities.order(:created_at)
    end
  end
end
