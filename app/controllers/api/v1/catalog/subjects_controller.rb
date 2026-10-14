# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/subjects
      class SubjectsController < Api::V1::PublicController
        def index
          rows = ::Catalog::SubjectQuery.new.call(term_uid: params[:term_uid])

          render_collection(rows, meta: { count: rows.size, term_uid: params[:term_uid]&.to_i })
        end
      end
    end
  end
end
