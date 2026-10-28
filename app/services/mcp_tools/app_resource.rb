# frozen_string_literal: true

module McpTools
  # The base of an MCP App resource (the MCP Apps extension, SEP-1865). A host
  # that supports the extension reads the resource and shows its HTML in a
  # sandboxed iframe next to the result of a tool that names it. See
  # docs/mcp.md, "Apps".
  #
  # The HTML is self-contained: inline CSS and JavaScript, no network. So the
  # resource declares no CSP domains, and the host applies its strictest CSP.
  # A template shares code with an include line, which this class replaces
  # with the file from app/views/mcp_apps/:
  #
  #   /* @include shared/base.css */
  #   // @include shared/app.js
  class AppResource < MCP::Resource
    DIRECTORY = Rails.root.join("app/views/mcp_apps")
    INCLUDE   = %r{^[ \t]*(?:/\* @include ([\w/.-]+) \*/|// @include ([\w/.-]+))[ \t]*$}

    class << self
      # The file of the template in app/views/mcp_apps/.
      def template(value = nil)
        value ? @template = value : @template
      end

      # The _meta of a tool that shows its result in this app.
      def tool_meta = MCP::Apps.tool_meta(resource_uri: uri, legacy: true)

      def contents
        MCP::Resource::TextContents.new(
          uri:       uri,
          mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
          text:      html,
          meta:      { ui: { prefersBorder: true } }
        )
      end

      def html
        DIRECTORY.join(template).read.gsub(INCLUDE) { DIRECTORY.join(Regexp.last_match(1) || Regexp.last_match(2)).read }
      end
    end
  end
end
