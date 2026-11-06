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

    # The term of the term_uid param, or the default when the param is blank.
    # An unknown uid answers 404.
    def selected_term(default: Term.current)
      return default if params[:term_uid].blank?

      # to_s: a param such as term_uid[]=1 is an Array.
      Term.find_by(uid: params[:term_uid].to_s.to_i) || raise(ActiveRecord::RecordNotFound, "No term #{params[:term_uid]}")
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
