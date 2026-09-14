# frozen_string_literal: true

# The API catalog at /.well-known/api-catalog, in the linkset format of
# RFC 9727. An agent reads it to find each public API, a machine description
# of the API, the reference, and a health check.
#
# Each URL comes from the routes and the request host, the same as /llms.txt.
class ApiCatalogSerializer
  include Rails.application.routes.url_helpers

  # @param url_options [Hash] the controller's url_options, for the host.
  def initialize(url_options)
    @url_options = url_options
  end

  attr_reader :url_options

  def as_json(*)
    { linkset: [ rest_api, graphql_api ] }
  end

  private

  def rest_api
    {
      anchor:         URI.join(root_url, "api/v1/catalog").to_s,
      "service-desc": [ { href: api_openapi_url, type: "application/vnd.oai.openapi+json" } ],
      "service-doc":  reference,
      status:         health
    }
  end

  def graphql_api
    {
      anchor:         api_graphql_url,
      "service-desc": [ { href: api_graphql_schema_url, type: "text/plain" } ],
      "service-doc":  reference,
      status:         health
    }
  end

  def reference
    [
      { href: api_docs_url, type: "text/html" },
      { href: api_docs_url(format: :md), type: "text/markdown" }
    ]
  end

  def health
    [ { href: rails_health_check_url } ]
  end
end
