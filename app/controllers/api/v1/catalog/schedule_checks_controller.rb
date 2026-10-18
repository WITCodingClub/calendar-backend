# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/schedule_check?term_uid=202720&crn=20397,20401
      #
      # Checks a set of sections taken together. Catalog::ScheduleCheck has
      # the rules.
      class ScheduleChecksController < Api::V1::PublicController
        def show
          render_resource(::Catalog::ScheduleCheck.new(term_uid: params[:term_uid], crns: array_param(:crn)).call)
        end
      end
    end
  end
end
