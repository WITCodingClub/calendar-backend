# frozen_string_literal: true

require "rails_helper"

# The week grid MCP App (McpTools::WeekGridApp) in a fake host
# (spec/support/mcp_app_host.rb), with a real tool result.
RSpec.describe "MCP week grid app", type: :system do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  it "draws the sections of check_schedule and marks the conflict" do
    calc  = create(:course, term: term, crn: 20397, subject: "MATH", course_number: 1750, title: "Calculus I")
    phys  = create(:course, term: term, crn: 20401, subject: "PHYS", course_number: 1250, title: "Physics I")
    other = create(:course, term: term, crn: 20500, subject: "COMP", course_number: 1000, title: "Programming")
    create(:course_meeting_time, course: calc, day_of_week: :monday, begin_time: 900, end_time: 1015)
    create(:course_meeting_time, course: calc, day_of_week: :monday, begin_time: 1400, end_time: 1550)
    create(:course_meeting_time, course: phys, day_of_week: :monday, begin_time: 1000, end_time: 1115)
    create(:course_meeting_time, course: other, day_of_week: :wednesday, begin_time: 1300, end_time: 1415)

    start_host(McpTools::WeekGridApp)
    send_tool_result(tool_result(McpTools::CheckSchedule, user, term_uid: term.uid, crns: [ 20397, 20401, 20500 ]))

    within_frame("app") do
      expect(page).to have_css("h1", text: "Schedule check")
      expect(page).to have_css("#summary", text: "9:00 AM to 3:50 PM")
      expect(page).to have_css("#summary", text: "1 conflict")

      monday = find("[role='list'][aria-label='Monday']")
      expect(monday).to have_css(".block.conflict[data-crn='20397']", text: "Conflict")
      expect(monday).to have_css(".block.conflict[data-crn='20401']", text: "Conflict")
      # The two blocks share the column, so each one is narrow with a short time.
      expect(monday).to have_css(".block.narrow[data-crn='20397'] .time", exact_text: "9:00–10:15")
      expect(page).to have_css(".hour.top", text: "9 AM", visible: :all)
      # The second Monday meeting of CRN 20397 does not overlap anything.
      expect(monday).to have_css(".block:not(.conflict)[data-crn='20397']", text: "2:00 – 3:50 PM")
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

    start_host(McpTools::WeekGridApp)
    send_tool_result(tool_result(McpTools::MyCourses, user, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: "My courses, #{term.name}")
      expect(find("[role='list'][aria-label='Tuesday']")).to have_css(".block", text: "11:00 AM – 12:15 PM")
      expect(find("[role='list'][aria-label='Monday']")).to have_no_css(".block")
      # The all-day placeholder of a section with no set time is not a block.
      expect(find("[role='list'][aria-label='Wednesday']")).to have_no_css(".block")
      expect(page).to have_css(".notes li.plain", text: "No set meeting time: COMP 3000")
      expect(page).to have_css(".advisory", text: "program director and your academic advisor")
      expect(page).to have_css(".advisory", text: "last refreshed from Banner on Oct 21, 4:12 AM")
    end
  end

  it "gives a lecture and its lab the same color" do
    lecture = create(:course, term: term, crn: 20100, subject: "CHEM", course_number: 1100, section_number: "13E")
    lab     = create(:course, term: term, crn: 20101, subject: "CHEM", course_number: 1100, section_number: "15E")
    other   = create(:course, term: term, crn: 20200, subject: "MATH", course_number: 2600, section_number: "6")
    create(:course_meeting_time, course: lecture, day_of_week: :monday, begin_time: 900, end_time: 950)
    create(:course_meeting_time, course: lab, day_of_week: :tuesday, begin_time: 800, end_time: 945)
    create(:course_meeting_time, course: other, day_of_week: :monday, begin_time: 1000, end_time: 1110)

    start_host(McpTools::WeekGridApp)
    send_tool_result(tool_result(McpTools::CheckSchedule, user, term_uid: term.uid, crns: [ 20100, 20101, 20200 ]))

    within_frame("app") do
      expect(page).to have_css(".block.c0[data-crn='20100']")
      expect(page).to have_css(".block.c0[data-crn='20101']")
      expect(page).to have_css(".block.c1[data-crn='20200']")
    end
  end

  it "says that a past term is no longer refreshed" do
    course = create(:course, term: term, crn: 20397)
    create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 900, end_time: 1015)
    allow(Term).to receive(:current).and_return(create(:term, year: term.year + 1))

    start_host(McpTools::WeekGridApp)
    send_tool_result(tool_result(McpTools::CheckSchedule, user, term_uid: term.uid, crns: [ 20397 ]))

    within_frame("app") do
      expect(page).to have_css(".advisory", text: "This term has ended, so WIT Calendar no longer refreshes its section data.")
    end
  end

  it "shows the error text of a tool error" do
    start_host(McpTools::WeekGridApp)
    send_tool_result(content: [ { type: "text", text: "No term with uid 1." } ], isError: true)

    within_frame("app") do
      expect(page).to have_css("[role='alert']", text: "No term with uid 1.")
    end
  end

  it "takes the theme and the style variables of the host" do
    start_host(McpTools::WeekGridApp, theme: "dark", variables: { "--color-background-primary" => "rgb(1, 2, 3)" })

    within_frame("app") do
      expect(page).to have_css("html[data-theme='dark']")
      expect(page.evaluate_script("getComputedStyle(document.body).backgroundColor")).to eq("rgb(1, 2, 3)")
    end
  end
end
