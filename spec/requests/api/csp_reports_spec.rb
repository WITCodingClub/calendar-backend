# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/csp_reports" do
  def count(directive) = Yabeda.calendar.csp_reports_total.get(directive: directive) || 0

  def post_report(body, content_type)
    post "/api/csp_reports", params: body, headers: { "CONTENT_TYPE" => content_type }
  end

  let(:log) { StringIO.new }

  around do |example|
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    example.run
  ensure
    Rails.logger = original
  end

  describe "a report-uri report (application/csp-report)" do
    let(:body) { file_fixture("csp_reports/report_uri.json").read }

    it "answers 204 and counts the report by directive" do
      expect { post_report(body, "application/csp-report") }.to change { count("script-src-elem") }.by(1)

      expect(response).to have_http_status(:no_content)
    end

    it "logs one line without the query strings" do
      post_report(body, "application/csp-report")

      lines = log.string.lines.grep(/CSP violation/)
      expect(lines.size).to eq(1)
      expect(lines.first).to include("directive=script-src-elem", "blocked=https://cdn.example.com/widget.js", "document=/dashboard")
      expect(lines.first).not_to include("secret")
    end
  end

  describe "a Reporting API report (application/reports+json)" do
    let(:body) { file_fixture("csp_reports/reporting_api.json").read }

    it "answers 204 and counts only the CSP reports in the batch" do
      expect { post_report(body, "application/reports+json") }.to change { count("script-src-elem") }.by(1)

      expect(response).to have_http_status(:no_content)
    end

    it "names the page by its route, so the token in the path stays out of the log" do
      post_report(body, "application/reports+json")

      line = log.string.lines.grep(/CSP violation/).sole
      expect(line).to include("blocked=inline", "document=feeds/calendars#show")
      expect(line).not_to include("feed-token-123")
    end
  end

  it "counts a directive it does not know as other" do
    body = { "csp-report" => { "effective-directive" => "made-up-directive", "document-uri" => "https://calendar.witcc.dev/" } }.to_json

    expect { post_report(body, "application/csp-report") }.to change { count("other") }.by(1)
  end

  it "refuses a body over the size limit and counts nothing" do
    body = { "csp-report" => { "effective-directive" => "img-src", "blocked-uri" => "https://x.example/#{'a' * 40_000}" } }.to_json

    expect { post_report(body, "application/csp-report") }.not_to(change { count("img-src") })

    expect(response).to have_http_status(:content_too_large)
    expect(response.parsed_body["code"]).to eq("CONTENT_TOO_LARGE")
  end

  it "refuses a body that is not JSON" do
    post_report("not json", "application/csp-report")

    expect(response).to have_http_status(:bad_request)
  end

  it "refuses another content type" do
    post_report(file_fixture("csp_reports/report_uri.json").read, "text/plain")

    expect(response).to have_http_status(:unsupported_media_type)
  end
end
