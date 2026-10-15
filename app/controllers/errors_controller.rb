# frozen_string_literal: true

# Renders the error pages. config.exceptions_app sends every unhandled error
# here, including a request for a path that has no route.
#
# It inherits ActionController::Base, not ApplicationController. The
# modern-browser guard there answered a missing path with 406 to curl and to
# agents, so they never got the 404.
class ErrorsController < ActionController::Base
  include MarkdownNegotiation

  # The error pages exist only as HTML. A request for a missing /icon.png or
  # .woff2 file has a non-HTML format, and without formats: :html it raises a
  # missing template error and returns 500 instead of the real status.
  layout "error"

  helper_method :signed_in_for_error_page?

  def unauthorized
    render status: :forbidden, formats: :html
  end

  # A client that ranks HTML first, such as a browser, gets the HTML page. Any
  # other client gets a short markdown body that points to the files that
  # agents read first.
  def not_found
    response.headers["Vary"] = "Accept"

    if preferred_document_type == Mime[:html]
      render status: :not_found, formats: :html
    else
      render status: :not_found, formats: :md, layout: false
    end
  end

  def unprocessable_entity
    render status: :unprocessable_entity, formats: :html
  end

  def internal_server_error
    render status: :internal_server_error, formats: :html
  end

  private

  # Picks "Back to dashboard" or "Go to home page". The session lookup reads
  # the database, and a 500 page can be the result of a database outage. The
  # page must still render, so a database error counts as signed out.
  def signed_in_for_error_page?
    return @signed_in_for_error_page if defined?(@signed_in_for_error_page)

    @signed_in_for_error_page = user_signed_in?
  rescue ActiveRecord::ActiveRecordError => e
    Rails.error.report(e, handled: true, context: { error_page: action_name })
    @signed_in_for_error_page = false
  end
end
