# frozen_string_literal: true

# Content Security Policy. See the Securing Rails Applications Guide:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# The policy is in report-only mode: browsers do not block anything. They send
# each violation to Api::CspReportsController, which logs one line and counts
# it in calendar_csp_reports_total. Turn enforcement on in a follow-up, when
# the reports show no violation from the app's own pages.
#
# The hosts below are all that the app's pages load:
#
# - script-src: cdn.jsdelivr.net for Mermaid on the docs pages
#   (layouts/docs.html.erb imports it with a dynamic import, which a nonce does
#   not cover). Every inline <script>, and the Tailwind CDN script on the error
#   pages, carries the nonce instead of a host entry.
# - style-src: 'unsafe-inline', because the views and the engines use inline
#   style attributes, and Mermaid and the Tailwind CDN add <style> elements.
#   A style-src nonce would make browsers ignore 'unsafe-inline'.
# - img-src: wit.edu for the faculty photos (Faculties::Directory) and data:
#   for the SVG and icon data URIs.
# - form-action: Google and Microsoft sign-in. A form that redirects to
#   another origin needs that origin here. "Sign in with Microsoft" is a POST
#   that redirects to login.microsoftonline.com.
#
# The mounted engines (Mission Control Jobs, Blazer, PgHero, Audits1984,
# letter_opener_web) put the nonce on their inline scripts, and Flipper UI
# loads only its own script files, so the same policy fits them.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.object_src      :none
    policy.frame_ancestors :self
    policy.frame_src       :self
    policy.form_action     :self, "https://accounts.google.com", "https://login.microsoftonline.com"
    policy.script_src      :self, "https://cdn.jsdelivr.net/npm/mermaid@11/"
    policy.style_src       :self, :unsafe_inline
    policy.img_src         :self, :data, "https://wit.edu", "https://*.wit.edu"
    policy.font_src        :self, :data
    policy.connect_src     :self
    policy.manifest_src    :self
    policy.report_uri      "/api/csp_reports"
  end

  # One nonce per session, not per request. Turbo Drive swaps the body
  # without a new document, so the page keeps the policy (and the nonce) of
  # the first full load. A per-request nonce would block every inline script
  # on a page that Turbo shows after that. A visitor with no session gets a
  # random nonce on each page, so a page with an inline script that such a
  # visitor can reach through Turbo (users/sessions/new) sets
  # turbo-visit-control to reload.
  config.content_security_policy_nonce_generator = lambda do |request|
    request.session.id.to_s.presence || SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy_report_only = true
end
