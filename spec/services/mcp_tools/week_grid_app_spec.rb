# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::WeekGridApp do
  let(:contents) { described_class.contents.to_h }

  it "is a ui:// resource with the MCP App MIME type" do
    expect(described_class.uri).to start_with(MCP::Apps::URI_SCHEME)
    expect(described_class.mime_type).to eq("text/html;profile=mcp-app")
    expect(contents).to include(uri: described_class.uri, mimeType: "text/html;profile=mcp-app")
  end

  it "returns a whole HTML document" do
    expect(contents[:text]).to start_with("<!DOCTYPE html>").and end_with("</html>\n")
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
    expect(described_class.tool_meta[:ui]).to eq(resourceUri: described_class.uri)
  end
end
