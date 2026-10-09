# frozen_string_literal: true

module Dashboard
  class SchedulesController < Dashboard::ApplicationController
    include ScheduleLoading

    def show
      authorize current_user, :show?

      @schedule = build_schedule_for(current_user)
    end
  end
end
