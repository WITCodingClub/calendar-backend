# frozen_string_literal: true

# Serves the files that search engines and AI agents read first: /robots.txt,
# /sitemap.xml, /llms.txt, and the RFC 9727 API catalog at
# /.well-known/api-catalog.
#
# The files are templates, not files in public/, so each URL inside them comes
# from the routes and the request host. A static file would name one host and
# could point at a path that no longer exists.
#
# It inherits ActionController::Base, the same as DocsController. A crawler
# sends no session, and the modern-browser guard on the app pages could refuse
# a crawler that it does not recognize.
class DiscoveryController < ActionController::Base
  CACHE_AGE = 1.hour

  # RFC 9727 section 5 registers this media type and profile for the catalog.
  LINKSET_TYPE = %(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")

  before_action { expires_in CACHE_AGE, public: true }

  def robots; end

  def sitemap; end

  def llms; end

  # RFC 9727 section 2 asks for the api-catalog link on the response too, so a
  # HEAD request finds the catalog without the body.
  def api_catalog
    response.headers["Link"] = %(<#{api_catalog_url}>; rel="api-catalog")
    render content_type: LINKSET_TYPE
  end
end
