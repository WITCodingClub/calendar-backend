# frozen_string_literal: true

require "rails_helper"

# calendar-website renders the HTML pages from these markdown responses.
RSpec.describe "Docs", type: :request do
  describe "GET /docs/api.md" do
    it "returns the markdown source without a sign-in" do
      get "/docs/api.md"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/markdown")
      expect(response.charset).to eq("utf-8")
      expect(response.body).to eq(DocsController::SOURCE.read)
    end

    it "lets a proxy cache the markdown" do
      get "/docs/api.md"

      expect(response.headers["Cache-Control"]).to include("public")
    end
  end

  describe "GET /docs/api" do
    # Rails gets this path only when the website is down, so a reader still
    # gets the reference.
    it "returns the markdown source to a browser too" do
      accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      get "/docs/api", headers: { "Accept" => accept }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to eq(DocsController::SOURCE.read)
    end

    it "refuses a format the reference does not have" do
      get "/docs/api.json"

      expect(response).to have_http_status(:not_acceptable)
    end

    it "sends a client to the reference from /docs" do
      get "/docs"

      expect(response).to redirect_to("/docs/api")
    end
  end

  describe "GET /docs/mcp.md" do
    it "returns the markdown source of the MCP guide" do
      get "/docs/mcp.md"

      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to eq(Rails.root.join("docs/mcp.md").read)
    end
  end

  describe "diagrams" do
    # Mermaid turns accTitle and accDescr into the SVG <title> and <desc>, the
    # text alternative a screen reader reads.
    DocsController::PAGES.each do |key, source|
      it "gives each diagram on the #{key} page a text alternative" do
        diagrams = source.read.scan(/^```mermaid\n(.*?)^```/m).flatten

        expect(diagrams).not_to be_empty
        expect(diagrams).to all(match(/^\s*accTitle: \S/).and(match(/^\s*accDescr: \S/)))
      end
    end
  end
end
