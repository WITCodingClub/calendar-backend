# frozen_string_literal: true

module Api
  module V1
    module Catalog
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
