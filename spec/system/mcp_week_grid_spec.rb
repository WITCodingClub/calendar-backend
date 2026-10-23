# frozen_string_literal: true

require "rails_helper"

# The week grid MCP App (McpTools::WeekGridApp) in a fake host. The spec page
# puts the template in an iframe and answers its postMessage requests the way
# an MCP Apps host does: it answers ui/initialize, waits for
# ui/notifications/initialized, then sends the tool input and the tool result.
RSpec.describe "MCP week grid app", type: :system do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def start_host(theme: "light", variables: {})
    visit "about:blank"
    page.execute_script(<<~JS, McpTools::WeekGridApp.contents.text, theme, variables)
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

  def tool_result(tool, **arguments)
    response = tool.call(server_context: mcp_context(user), **arguments)
    { content: response.content, structuredContent: response.structured_content, isError: response.error? }
  end

  it "draws the sections of check_schedule and marks the conflict" do
    calc  = create(:course, term: term, crn: 20397, subject: "MATH", course_number: 1750, title: "Calculus I")
    phys  = create(:course, term: term, crn: 20401, subject: "PHYS", course_number: 1250, title: "Physics I")
    other = create(:course, term: term, crn: 20500, subject: "COMP", course_number: 1000, title: "Programming")
    create(:course_meeting_time, course: calc, day_of_week: :monday, begin_time: 900, end_time: 1015)
    create(:course_meeting_time, course: calc, day_of_week: :monday, begin_time: 1400, end_time: 1550)
    create(:course_meeting_time, course: phys, day_of_week: :monday, begin_time: 1000, end_time: 1115)
    create(:course_meeting_time, course: other, day_of_week: :wednesday, begin_time: 1300, end_time: 1415)

    start_host
    send_tool_result(tool_result(McpTools::CheckSchedule, term_uid: term.uid, crns: [ 20397, 20401, 20500 ]))

    within_frame("app") do
      expect(page).to have_css("h1", text: "Schedule check")
      expect(page).to have_css("#summary", text: "9:00 AM to 3:50 PM")
      expect(page).to have_css("#summary", text: "1 conflict")

      monday = find("[role='list'][aria-label='Monday']")
      expect(monday).to have_css(".block.conflict[data-crn='20397']", text: "Conflict")
      expect(monday).to have_css(".block.conflict[data-crn='20401']", text: "Conflict")
      # The second Monday meeting of CRN 20397 does not overlap anything.
      expect(monday).to have_css(".block:not(.conflict)[data-crn='20397']", text: "2:00 PM to 3:50 PM")
      expect(find("[role='list'][aria-label='Wednesday']")).to have_css(".block:not(.conflict)[data-crn='20500']")
      expect(page).to have_css(".notes li.danger",
                               text: "Conflict on Monday: CRN 20397 and CRN 20401 (9:00 AM to 10:15 AM, 10:00 AM to 11:15 AM)")
    end

    wait_for_host_message("ui/notifications/size-changed")
  end

  it "draws my_courses on the days each class meets" do
    course = create(:course, term: term, subject: "COMP", course_number: 2000, title: "Data Structures")
    create(:course_meeting_time, course: course, day_of_week: :tuesday, begin_time: 1100, end_time: 1215)
    create(:enrollment, user: user, course: course)
    online = create(:course, term: term, subject: "COMP", course_number: 3000, title: "Online Topics")
    create(:course_meeting_time, course: online, day_of_week: :wednesday, begin_time: 1201, end_time: 2359)
    create(:enrollment, user: user, course: online)
    term.update!(sections_synced_at: Time.zone.parse("2026-10-21 04:12"))
    allow(Term).to receive(:current).and_return(term)

    start_host
    send_tool_result(tool_result(McpTools::MyCourses, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: "My courses")
      expect(find("[role='list'][aria-label='Tuesday']")).to have_css(".block", text: "11:00 AM to 12:15 PM")
      expect(find("[role='list'][aria-label='Monday']")).to have_no_css(".block")
      # The all-day placeholder of a section with no set time is not a block.
      expect(find("[role='list'][aria-label='Wednesday']")).to have_no_css(".block")
      expect(page).to have_css(".notes li.plain", text: "No set meeting time: COMP 3000")
      expect(page).to have_css(".advisory", text: "program director and your academic advisor")
      expect(page).to have_css(".advisory", text: "last refreshed from Banner on Oct 21, 4:12 AM")
    end
  end

  it "says that a past term is no longer refreshed" do
    course = create(:course, term: term, crn: 20397)
    create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 900, end_time: 1015)
    allow(Term).to receive(:current).and_return(create(:term, year: term.year + 1))

    start_host
    send_tool_result(tool_result(McpTools::CheckSchedule, term_uid: term.uid, crns: [ 20397 ]))

    within_frame("app") do
      expect(page).to have_css(".advisory", text: "This term has ended, so WIT Calendar no longer refreshes its section data.")
    end
  end

  it "shows the error text of a tool error" do
    start_host
    send_tool_result(content: [ { type: "text", text: "No term with uid 1." } ], isError: true)

    within_frame("app") do
      expect(page).to have_css("[role='alert']", text: "No term with uid 1.")
    end
  end

  it "takes the theme and the style variables of the host" do
    start_host(theme: "dark", variables: { "--color-background-primary" => "rgb(1, 2, 3)" })

    within_frame("app") do
      expect(page).to have_css("html[data-theme='dark']")
      expect(page.evaluate_script("getComputedStyle(document.body).backgroundColor")).to eq("rgb(1, 2, 3)")
    end
  end
end
