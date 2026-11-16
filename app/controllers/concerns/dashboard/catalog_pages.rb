# frozen_string_literal: true

module Dashboard
  # Shared by the read-only catalog pages (#797): courses, instructors, finals,
  # and university events. The pages show public data, so a user with no
  # processed courses can open them too.
  module CatalogPages
    extend ActiveSupport::Concern

    PER_PAGE = 25

    included do
      skip_before_action :require_processed_courses
    end

    private

    # The term of the term_uid param. An unknown uid answers 404. Without the
    # param: the current term when it is one of offered, else the newest of
    # offered. Without offered, no term.
    def selected_term(offered = nil)
      # to_s: a param such as term_uid[]=1 is an Array.
      return Term.find_by_uid!(params[:term_uid].to_s) if params[:term_uid].present?
      return nil if offered.nil?

      current = Term.current
      offered.include?(current) ? current : offered.first
    end

    # The terms of some sections, newest first.
    def offered_terms(sections)
      Term.where(id: sections.reorder(nil).select(:term_id)).reverse_chronological.to_a
    end

    # The terms for the term picker, newest first.
    def term_options
      Term.reverse_chronological
    end

    def page_param
      [ params[:page].to_s.to_i, 1 ].max
    end
  end
end
