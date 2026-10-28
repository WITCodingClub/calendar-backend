# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::AppResource do
  McpTools.app_resources.each do |app|
    describe app.name do
      let(:contents) { app.contents.to_h }

      it "is a ui:// resource with the MCP App MIME type" do
        expect(app.uri).to start_with(MCP::Apps::URI_SCHEME)
        expect(app.mime_type).to eq("text/html;profile=mcp-app")
        expect(contents).to include(uri: app.uri, mimeType: "text/html;profile=mcp-app")
      end

      it "returns a whole HTML document with the shared files in place" do
        expect(contents[:text]).to start_with("<!DOCTYPE html>").and end_with("</html>\n")
        expect(contents[:text]).not_to match(McpTools::AppResource::INCLUDE)
        expect(contents[:text]).to include("var App = (function () {", "--color-background-primary")
      end

      # The host CSP blocks every outside origin, because the resource declares
      # no CSP domains. A link to one would fail in the host.
      it "loads nothing from the network" do
        expect(contents[:text]).not_to match(/(?:src|href)\s*=\s*["']?(?:https?:)?\/\//i)
        expect(contents[:text]).not_to match(/url\(\s*["']?(?:https?:)?\/\//i)
        expect(contents[:text]).not_to match(/@import|fetch\(|XMLHttpRequest|WebSocket/)
        expect(contents[:_meta]).to eq(ui: { prefersBorder: true })
      end

      it "builds the tool _meta with the resource URI" do
        expect(app.tool_meta[:ui]).to eq(resourceUri: app.uri)
      end
    end
  end

  it "gives each app its own URI and name" do
    expect(McpTools.app_resources.map(&:uri).uniq.size).to eq(McpTools.app_resources.size)
    expect(McpTools.app_resources.map(&:name_value).uniq.size).to eq(McpTools.app_resources.size)
  end
end
