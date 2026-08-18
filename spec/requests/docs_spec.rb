# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Docs", type: :request do
  describe "GET /docs/api" do
    it "publishes the reference without a sign-in" do
      get "/docs/api"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Course Catalog API")
    end

    it "renders the markdown, so the page holds no raw syntax" do
      get "/docs/api"

      expect(response.body).to include("<table>")
      expect(response.body).to include("<code>")
      expect(response.body).not_to include("| Parameter |")
    end

    it "shows the pub_id filter, so the file and the page agree" do
      get "/docs/api"

      expect(response.body).to include("pub_id")
    end

    it "builds a menu from the headings" do
      get "/docs/api"

      expect(response.body).to include('aria-label="On this page"')
      expect(response.body).to match(/<a href="#[a-z0-9-]+">/)
    end

    it "keeps the diagram source, so it renders or stays readable" do
      get "/docs/api"

      expect(response.body).to include('<code class="mermaid">')
    end

    it "lets a proxy cache the page" do
      get "/docs/api"

      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "sends a client to the reference from /docs" do
      get "/docs"

      expect(response).to redirect_to("/docs/api")
    end
  end

  describe ".render_markdown" do
    it "gives every heading an id, so the menu can link to it" do
      document = DocsController.render_markdown("## Sections\n\ntext\n")

      expect(document[:headings]).to eq([ { id: "sections", text: "Sections" } ])
    end

    it "escapes raw HTML in the source" do
      document = DocsController.render_markdown("<script>alert(1)</script>\n")

      expect(document[:html]).not_to include("<script>")
    end
  end
end
