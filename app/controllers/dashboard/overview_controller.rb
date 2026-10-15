# frozen_string_literal: true

module Dashboard
  class OverviewController < Dashboard::ApplicationController
    # One step of the setup checklist on the Overview page (#698).
    SetupStep = Data.define(:title, :description, :done, :action)

    def index
      authorize current_user, :show?

      @current_term  = Term.current
      @next_term     = Term.next(@current_term)
      @enrollment_count = current_user.enrollments.where(term: @current_term).count if @current_term
      @has_calendar  = current_user.oauth_credentials.joins(:course_calendar).exists?
      @notifications_disabled = current_user.notifications_disabled?
      @setup_steps = setup_steps
    end

    private

    # The onboarding gate (#644) sends a user with no processed courses to the
    # onboarding page, so most users here have done the first step. Admins
    # skip the gate, and a new term needs a new import.
    def setup_steps
      processed = current_user.processed_courses?
      imported_this_term = @current_term ? @enrollment_count.positive? : processed
      extension = { label: "Get the extension", url: Rails.configuration.x.extension_install_url, external: true }

      [
        SetupStep.new(
          title: "Install the extension",
          description: "Add WIT Calendar to Chrome from the Chrome Web Store.",
          done: processed,
          action: extension
        ),
        SetupStep.new(
          title: "Import your schedule",
          description: @current_term ? "Open the extension and import your courses for #{@current_term.name}." : "Open the extension and import your courses.",
          done: imported_this_term,
          action: processed ? nil : extension
        ),
        SetupStep.new(
          title: "Connect a calendar",
          description: "Connect Google Calendar or Outlook to get your classes there. You can also subscribe to the ICS feed.",
          done: @has_calendar,
          action: { label: "Connect a calendar", url: dashboard_connected_accounts_path }
        )
      ]
    end
  end
end
