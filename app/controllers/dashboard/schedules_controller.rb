# frozen_string_literal: true

class Dashboard::SchedulesController < Dashboard::ApplicationController
  include ScheduleLoading

  def show
    authorize current_user, :show?

    @schedule = build_schedule_for(current_user)
  end
end
