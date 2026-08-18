# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/subjects
      class SubjectsController < Api::V1::PublicController
        def index
          scope = Course.active
          scope = scope.where(term_id: Term.where(uid: params[:term_uid].to_i).select(:id)) if params[:term_uid].present?

          rows = scope.group(:subject).count.sort_by { |subject, _| subject }

          render_collection(
            rows.map { |subject, count| { subject: subject, code: code_for(subject), section_count: count } },
            meta: { count: rows.size, term_uid: params[:term_uid]&.to_i }
          )
        end

        private

        # Stored as "Computer Science (COMP)"; students search by the code.
        def code_for(subject)
          subject =~ /\(([^)]+)\)/ ? ::Regexp.last_match(1) : subject
        end
      end
    end
  end
end
