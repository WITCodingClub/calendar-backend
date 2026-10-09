# frozen_string_literal: true

module Admin
  class RoomsController < Admin::ApplicationController
    def index
      authorize Room

      @rooms = Room.includes(:building).references(:building).order("buildings.name, rooms.number")
      @rooms = @rooms.where("rooms.number ILIKE ?", "%#{Room.sanitize_sql_like(params[:search].strip)}%") if params[:search].present?
      @rooms = @rooms.where(building_id: params[:building_id]) if params[:building_id].present?
      @rooms = @rooms.page(params[:page]).per(50)
      @buildings = Building.order(:name)
    end

    def show
      # rubocop:disable Rails/DynamicFindBy
      @room = Room.find_by_public_id!(params[:id])
      # rubocop:enable Rails/DynamicFindBy
      authorize @room

      courses = @room.meeting_times
                     .joins(:course)
                     .includes(:rooms, course: [ :term, :faculties ])
                     .map(&:course)
                     .uniq
                     .sort_by { |c| [ -c.term.year, -Term.season_position(c.term.season), c.title || "" ] }

      @courses_by_term = courses.group_by(&:term)
    end
  end
end
