# frozen_string_literal: true

module Api
  # Finds the term that params[:term_uid] names. Renders 400 without a uid and
  # 404 for an unknown one, and returns nil then. Call it, then
  # "return if performed?".
  module TermLookup
    extend ActiveSupport::Concern

    private

    def find_term_by_uid
      term_uid = params[:term_uid]

      if term_uid.blank?
        render_error "term_uid is required", status: :bad_request
        return nil
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render_error "Term not found", status: :not_found
        return nil
      end

      term
    end
  end
end
