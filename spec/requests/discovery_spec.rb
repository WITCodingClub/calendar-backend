# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Discovery files", type: :request do
  # A crawler that the modern-browser guard does not know.
  let(:crawler) { { "User-Agent" => "curl/8.7.1" } }

  describe "GET /robots.txt" do
    it "answers a crawler with plain text" do
      get "/robots.txt", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/plain")
    end

    it "allows every crawler to read the public pages" do
      get "/robots.txt", headers: crawler

      expect(response.body).to include("User-agent: *\nAllow: /\n")
      expect(response.body).not_to match(/^Disallow: \/$/)
    end

    it "keeps crawlers out of the pages that need a sign-in or a calendar token" do
      get "/robots.txt", headers: crawler

      %w[/admin /dashboard /users/ /calendar/].each do |path|
        expect(response.body).to include("Disallow: #{path}\n")
      end
    end

    it "does not disallow the public API or the reference" do
      get "/robots.txt", headers: crawler

      disallowed = response.body.scan(/^Disallow: (\S+)$/).flatten
      %w[/api/v1/catalog/terms /docs/api /docs/api.md /llms.txt /reports/sections].each do |path|
        expect(disallowed.none? { |prefix| path.start_with?(prefix) }).to be(true), "#{path} is disallowed"
      end
    end

    it "points crawlers at the sitemap on this host" do
      get "/robots.txt", headers: crawler

      expect(response.body).to include("Sitemap: http://example.com/sitemap.xml")
    end

    it "lets a proxy cache the file" do
      get "/robots.txt", headers: crawler

      expect(response.headers["Cache-Control"]).to include("public")
    end
  end

  describe "GET /sitemap.xml" do
    it "lists the API reference" do
      get "/sitemap.xml", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")

      locations = Nokogiri::XML(response.body).remove_namespaces!.xpath("//url/loc").map(&:text)
      expect(locations).to eq([ "http://example.com/docs/api" ])
    end
  end

  describe "GET /llms.txt" do
    let(:links) { response.body.scan(/\]\((http[^)]+)\)/).flatten }

    it "gives agents a markdown index of the site" do
      get "/llms.txt", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to start_with("# WIT Calendar\n\n> ")
    end

    it "sends agents to the markdown copy of the reference" do
      get "/llms.txt", headers: crawler

      expect(links).to include("http://example.com/docs/api.md")
    end

    it "links only to routes that exist" do
      get "/llms.txt", headers: crawler

      expect(links).not_to be_empty
      links.each do |link|
        path   = URI(link).path
        method = path == "/api/graphql" ? :post : :get
        route  = Rails.application.routes.recognize_path(path, method: method)

        expect(route[:controller]).not_to eq("api/catch_all"), "#{link} has no route"
      end
    end
  end
end
