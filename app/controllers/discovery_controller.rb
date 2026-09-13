# frozen_string_literal: true

# Serves the files that search engines and AI agents read first: /robots.txt,
# /sitemap.xml, and /llms.txt.
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

  before_action { expires_in CACHE_AGE, public: true }

  def robots; end

  def sitemap; end

  def llms; end
end
