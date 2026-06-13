# frozen_string_literal: true

module Admin
  class BuildingsController < Admin::ApplicationController
    def index
      authorize Building
      @buildings = Building.includes(:rooms).order(:abbreviation)
    end

    def sync
      authorize Building, :sync?
      TwentyFiveLiveSyncJob.perform_later
      redirect_to admin_buildings_path, notice: "25Live space sync queued."
    end

    def apply_formal_name
      authorize Building, :apply_formal_name?
      building = Building.find_by_public_id!(params[:id])

      unless building.formal_name.present?
        redirect_to admin_buildings_path, alert: "No 25Live formal name for #{building.abbreviation}."
        return
      end

      building.update!(name: building.formal_name)
      redirect_to admin_buildings_path, notice: "Updated #{building.abbreviation} to \"#{building.formal_name}\"."
    end

    def apply_all
      authorize Building, :apply_all?

      count = Building.where.not(formal_name: nil).where.not("name = formal_name").count
      Building.where.not(formal_name: nil).where.not("name = formal_name").find_each do |b|
        b.update!(name: b.formal_name)
      end

      redirect_to admin_buildings_path, notice: "Applied 25Live names to #{count} building#{"s" unless count == 1}."
    end
  end
end
