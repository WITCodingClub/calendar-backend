# frozen_string_literal: true

module Dashboard
  class SchedulesController < Dashboard::ApplicationController
    include ScheduleLoading

    def show
      authorize current_user, :show?

      @schedule = build_schedule_for(current_user)
      @extension_install_url = Rails.configuration.x.extension_install_url
    end
  end
end
