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

  # The passkey code is a Stimulus controller, so Turbo can show the page
  # with the nonce of an earlier page.
  it "has no inline script on the sign-in page" do
    get "/users/sign_in"

    scripts = Nokogiri::HTML(response.body).css("script").reject { |script| script["src"] || script["type"] == "importmap" }
    expect(scripts.map(&:text).join).not_to include("navigator.credentials")
    expect(response.body).to include('data-controller="passkey-sign-in"')
  end

  it "keeps the nonce in style-src out, so inline style attributes still work" do
    get "/users/sign_in"

    expect(policy[/style-src [^;]*/]).to eq("style-src 'self' 'unsafe-inline'")
  end

  it "passes the passkey page values to its Stimulus controller, not an inline script" do
    get "/passkey", params: { mode: "authenticate", redirect_uri: "https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/" }

    expect(response.body).to include('data-controller="passkey-ceremony"')
    expect(response.body).not_to include("navigator.credentials")
  end

  it "escapes a value that could close a tag on the passkey page" do
    get "/passkey", params: {
      mode: "authenticate",
      redirect_uri: "https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/",
      state: "</script><script>alert(1)</script>"
    }

    expect(response.body).not_to include("<script>alert(1)")
    expect(Nokogiri::HTML(response.body).at_css("[data-passkey-ceremony-state-value]")["data-passkey-ceremony-state-value"])
      .to eq("</script><script>alert(1)</script>")
  end

  it "puts the nonce on the inline scripts of the OAuth result pages" do
    get "/oauth/success", params: { email: "person@example.com", calendar_id: "</script>" }

    expect(response.body).to include(%(<script nonce="#{nonce}">))
    expect(response.body).not_to include('"</script>"')

    get "/oauth/failure", params: { error: "nope" }

    expect(response.body).to include(%(<script nonce="#{nonce}">))
  end

  it "allows scripts from no other host" do
    get "/404"

    expect(policy).to match(/script-src 'self' 'nonce-[^']+';/)
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
end
