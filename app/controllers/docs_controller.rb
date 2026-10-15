# frozen_string_literal: true

# Serves the markdown source of the public catalog API reference and the MCP
# server guide, and the machine descriptions of the API at
# /docs/api/openapi.json and /docs/api/schema.graphql.
#
# The HTML pages at /docs/api and /docs/mcp come from the calendar-website
# Worker. It fetches /docs/<page>.md from here and renders it, so the markdown
# in docs/ stays the one source, and an endpoint and its reference change in
# one pull request. The rproxy Worker sends a request here only when the
# website answers 400 or higher, so /docs/api and /docs/mcp reach Rails only
# when the website is down. Then they return the markdown too.
#
# It inherits ActionController::Base, not ApplicationController. The page needs
# no sign-in and no Pundit, and the modern-browser guard on the app pages would
# refuse curl and any other script that reads the reference.
class DocsController < ActionController::Base
  SOURCE    = Rails.root.join("docs/public-catalog-api.md")
  OPENAPI   = Rails.root.join("docs/public-catalog-api.openapi.yml")
  CACHE_AGE = 1.hour

  # The markdown source of each page.
  PAGES = {
    api: SOURCE,
    mcp: Rails.root.join("docs/mcp.md")
  }.freeze

  def api
    render_source(:api)
  end

  def mcp
    render_source(:mcp)
  end

  # The file names no host. The server URL comes from the request, the same as
  # the URLs in /llms.txt.
  def openapi
    expires_in CACHE_AGE, public: true

    document = YAML.safe_load_file(OPENAPI)
    document["servers"] = [ { "url" => root_url.delete_suffix("/") } ]

    render json: document, content_type: "application/vnd.oai.openapi+json"
  end

  # The SDL comes from the schema class that runs the queries, so it cannot
  # drift from the endpoint.
  def graphql_schema
    expires_in CACHE_AGE, public: true
    render plain: CatalogSchema.to_definition
  end

  private

  def render_source(key)
    raise ActionController::UnknownFormat unless params[:format].in?([ nil, "md" ])

    source = PAGES.fetch(key)
    raise ActionController::RoutingError, "No #{key} docs page" unless source.exist?

    expires_in CACHE_AGE, public: true
    render plain: source.read, content_type: "text/markdown"
  end
end
