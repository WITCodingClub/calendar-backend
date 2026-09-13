# frozen_string_literal: true

module Admin
  class BuildingsController < Admin::ApplicationController
    def index
      authorize Building
      @buildings = Building.physical.includes(:rooms).order(:abbreviation)
      @sync_in_progress = TwentyFiveLiveSyncJob.in_progress?
      @last_checked_at = @buildings.filter_map(&:twenty_five_live_checked_at).max
    end

    def sync
      authorize Building, :sync?

      if TwentyFiveLiveSyncJob.in_progress?
        redirect_to admin_buildings_path, notice: "A 25Live space sync is already running."
        return
      end

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

      mismatched = Building.physical.where.not(formal_name: nil).where.not("name = formal_name")
      count = mismatched.count
      mismatched.find_each do |b|
        b.update!(name: b.formal_name)
      end

      redirect_to admin_buildings_path, notice: "Applied 25Live names to #{count} building#{"s" unless count == 1}."
    end
  end
end
