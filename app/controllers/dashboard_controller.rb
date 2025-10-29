class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @enrollments = current_user.enrollments.includes(:course)
  end
end
