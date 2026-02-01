# frozen_string_literal: true

module Admin
  class BuildingsController < Admin::ApplicationController
    def index
      @buildings = Building.order(:name).page(params[:page]).per(7)
    end

    def show
      # rubocop:disable Rails/DynamicFindBy
      @building = Building.find_by_public_id!(params[:id])
      # rubocop:enable Rails/DynamicFindBy
      @rooms = @building.rooms.order(:number)

      # Get all courses that meet in this building, grouped by term
      room_ids = @building.rooms.pluck(:id)
      courses = Course.joins(:meeting_times, :term)
                      .where(meeting_times: { room_id: room_ids })
                      .includes(:term, :faculties, meeting_times: :room)
                      .distinct
                      .order("terms.year DESC, terms.season DESC, courses.title")

      @courses_by_term = courses.group_by(&:term)
    end

  end
end
