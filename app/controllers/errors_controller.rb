# frozen_string_literal: true

class ErrorsController < ApplicationController
  # The error pages exist only as HTML. A request for a missing /icon.png or
  # .woff2 file has a non-HTML format, and without formats: :html it raises a
  # missing template error and returns 500 instead of the real status.
  layout false

  def unauthorized
    render status: :forbidden, formats: :html
  end

  def not_found
    render status: :not_found, formats: :html
  end

  def unprocessable_entity
    render status: :unprocessable_entity, formats: :html
  end

  def internal_server_error
    render status: :internal_server_error, formats: :html
  end
end
