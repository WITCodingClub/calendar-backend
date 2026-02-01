# frozen_string_literal: true

module Admin
  class RoomsController < Admin::ApplicationController
    def index
      @rooms = Room.includes(:building).order("buildings.name, rooms.number").page(params[:page]).per(7)
    end

    def show
      # rubocop:disable Rails/DynamicFindBy
      @room = Room.find_by_public_id!(params[:id])
      # rubocop:enable Rails/DynamicFindBy

      # Get courses that meet in this room, grouped by term
      courses = @room.meeting_times
                     .joins(:course)
                     .includes(course: [:term, :faculties])
                     .map(&:course)
                     .uniq
                     .sort_by { |c| [-c.term.year, -(Term.seasons[c.term.season] || 0), c.title || ""] }

      @courses_by_term = courses.group_by(&:term)
    end

  end
end
