# frozen_string_literal: true

# Chooses between markdown and HTML from the Accept header.
#
# Rails ignores an Accept header that also lists */*, and most agents send one,
# for example "text/markdown, text/html, */*". This concern reads the header
# itself and compares only the two document types.
module MarkdownNegotiation
  extend ActiveSupport::Concern

  private

  # @return [Mime::Type, nil] Mime[:md] or Mime[:html], whichever the client
  #   ranks higher, or nil when the header names neither.
  def preferred_document_type
    types = Mime::Type.parse(request.headers["Accept"].to_s)
    types.find { |type| type == Mime[:md] || type == Mime[:html] }
  rescue Mime::Type::InvalidMimeType
    nil
  end
end
