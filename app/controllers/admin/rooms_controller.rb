# frozen_string_literal: true

module Admin
  class RoomsController < Admin::ApplicationController
    def index
      @rooms = Room.includes(:building).order("buildings.name, rooms.number").page(params[:page])
    end

  end
end
