# frozen_string_literal: true

# A fake MCP Apps host for the system specs of the MCP App templates
# (McpTools::AppResource). start_host puts the template in an iframe and
# answers its postMessage requests the way a host does: it answers
# ui/initialize and waits for ui/notifications/initialized. send_tool_result
# then sends the tool input and the tool result.
module McpAppHost
  def start_host(app, theme: "light", variables: {})
    visit "about:blank"
    page.execute_script(<<~JS, app.contents.text, theme, variables)
      const [html, theme, variables] = arguments
      const log = document.createElement("ul")
      log.id = "host-log"
      document.body.appendChild(log)
      const frame = document.createElement("iframe")
      frame.id = "app"
      frame.style.width = "900px"
      frame.style.height = "700px"
      window.addEventListener("message", (event) => {
        if (event.source !== frame.contentWindow) return
        const message = event.data
        const item = document.createElement("li")
        item.dataset.method = message.method || "response"
        log.appendChild(item)
        if (message.method === "ui/initialize") {
          frame.contentWindow.postMessage({
            jsonrpc: "2.0", id: message.id,
            result: {
              protocolVersion: "2026-01-26", hostInfo: { name: "spec", version: "1" }, hostCapabilities: {},
              hostContext: { theme: theme, styles: { variables: variables } }
            }
          }, "*")
        }
      })
      frame.srcdoc = html
      document.body.appendChild(frame)
    JS
    expect(page).to have_css("iframe#app")
    wait_for_host_message("ui/notifications/initialized")
  end

  # The host lists each message from the app in #host-log, so the matchers
  # can wait for one.
  def wait_for_host_message(method)
    expect(page).to have_css("#host-log li[data-method='#{method}']", visible: :all)
  end

  def send_tool_result(result)
    page.execute_script(<<~JS, result.as_json)
      const frame = document.getElementById("app")
      frame.contentWindow.postMessage({ jsonrpc: "2.0", method: "ui/notifications/tool-input", params: { arguments: {} } }, "*")
      frame.contentWindow.postMessage({ jsonrpc: "2.0", method: "ui/notifications/tool-result", params: arguments[0] }, "*")
    JS
  end

  # Calls the tool as user and returns the result the way a host sends it.
  def tool_result(tool, user, **arguments)
    response = tool.call(server_context: mcp_context(user), **arguments)
    { content: response.content, structuredContent: response.structured_content, isError: response.error? }
  end
end

RSpec.configure do |config|
  config.include McpAppHost, type: :system
end
