# frozen_string_literal: true

# Serves the files that search engines and AI agents read first: /robots.txt,

# /sitemap.xml, /llms.txt, /auth.md, /.well-known/security.txt, and the API catalog at
# /.well-known/api-catalog.

# The files are templates, not files in public/, so each URL inside them comes
# from the routes and the request host. A static file would name one host and
# could point at a path that no longer exists.
#
# It inherits ActionController::Base, the same as DocsController. A crawler
# sends no session, and the modern-browser guard on the app pages could refuse
# a crawler that it does not recognize.
class DiscoveryController < ActionController::Base
  CACHE_AGE = 1.hour

  # RFC 9727 asks for this profile on the catalog media type.
  API_CATALOG_PROFILE = "https://www.rfc-editor.org/info/rfc9727"

  before_action { expires_in CACHE_AGE, public: true }

  def robots; end

  def sitemap; end

  def llms; end

  # RFC 9116 wants an Expires date less than one year ahead. The date moves
  # forward on the first day of each month, so a proxy cache stays correct
  # and the file never goes stale while the site runs.
  def security
    @expires = Time.current.utc.beginning_of_month.advance(years: 1)
  end

  # A HEAD request gets the Link header only. RFC 9727 names the relation.
  def api_catalog
    response.headers["Link"] = %(<#{api_catalog_url}>; rel="api-catalog")

    render json:         ApiCatalogSerializer.new(url_options).as_json,
           content_type: %(application/linkset+json; profile="#{API_CATALOG_PROFILE}")
  end

  # How an agent gets a credential for the personal API. The service has no
  # OAuth authorization server, so the file stands alone and there is no
  # /.well-known/oauth-protected-resource document.
  def auth; end
end
