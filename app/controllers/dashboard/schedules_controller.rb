# frozen_string_literal: true

module Dashboard
  class SchedulesController < Dashboard::ApplicationController
    def show
      authorize current_user, :show?

      @schedule = Courses::Schedule.build(current_user, **schedule_params)
      @extension_install_url = Rails.configuration.x.extension_install_url
    end
  end
end
