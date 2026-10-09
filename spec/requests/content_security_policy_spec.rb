# frozen_string_literal: true

require "rails_helper"

# config/initializers/content_security_policy.rb. The policy is report-only
# until the reports are clean, so a page must send it under that header name.
RSpec.describe "Content Security Policy" do
  def policy = response.headers["Content-Security-Policy-Report-Only"]
  def nonce = policy[/'nonce-([^']+)'/, 1]

  it "sends the report-only policy with a script nonce on an HTML page" do
    get "/users/sign_in"

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Security-Policy"]).to be_nil
    expect(policy).to include("script-src 'self'", "object-src 'none'", "report-uri /api/csp_reports")
    expect(nonce).to be_present
  end

  it "puts the nonce on the inline script of the sign-in page" do
    get "/users/sign_in"

    expect(response.body).to include(%(<script nonce="#{nonce}">))
  end

  it "keeps the nonce in style-src out, so inline style attributes still work" do
    get "/users/sign_in"

    expect(policy[/style-src [^;]*/]).to eq("style-src 'self' 'unsafe-inline'")
  end

  it "puts the nonce on the inline script of the passkey page" do
    get "/passkey", params: { mode: "authenticate", redirect_uri: "https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/" }

    expect(response.body).to include(%(<script type="module" nonce="#{nonce}">))
  end

  it "escapes a value that could close the script tag on the passkey page" do
    get "/passkey", params: {
      mode: "authenticate",
      redirect_uri: "https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/",
      state: "</script><script>alert(1)</script>"
    }

    expect(response.body).not_to include("</script><script>alert(1)")
    expect(response.body).to include('</script>')
  end

  it "puts the nonce on the inline scripts of the OAuth result pages" do
    get "/oauth/success", params: { email: "person@example.com", calendar_id: "</script>" }

    expect(response.body).to include(%(<script nonce="#{nonce}">))
    expect(response.body).not_to include('"</script>"')

    get "/oauth/failure", params: { error: "nope" }

    expect(response.body).to include(%(<script nonce="#{nonce}">))
  end

  it "puts the nonce on the docs scripts and lets Mermaid load from its CDN path" do
    get "/docs/api"

    expect(response.body).to include(%(<script type="module" nonce="#{nonce}">))
    expect(response.body).to include(%(<script type="application/ld+json" nonce="#{nonce}">))
    expect(policy).to include("https://cdn.jsdelivr.net/npm/mermaid@11/")
  end

  # Turbo Drive keeps the policy of the first full page load, so a page that
  # Turbo shows later must use the same nonce.
  it "keeps the same nonce for one signed-in session" do
    sign_in create(:user, :with_processed_courses)
    get "/dashboard"

    get "/dashboard"
    first = nonce
    get "/dashboard"

    expect(response).to have_http_status(:ok)
    expect(nonce).to eq(first)
  end

  # A visitor with no session gets a new nonce on each page, so the sign-in
  # page asks Turbo for a full page load.
  it "makes Turbo load the sign-in page in full" do
    get "/users/sign_in"

    expect(response.body).to include('<meta name="turbo-visit-control" content="reload">')
  end
end
