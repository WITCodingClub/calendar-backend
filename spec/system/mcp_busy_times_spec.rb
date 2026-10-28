# frozen_string_literal: true

require "rails_helper"

# The busy times MCP App (McpTools::BusyTimesApp) in a fake host
# (spec/support/mcp_app_host.rb), with a real tool result.
RSpec.describe "MCP busy times app", type: :system do
  let(:user) { create(:user) }

  it "draws a row for each day of my_busy_times" do
    exam = create(:final_exam, exam_date: Date.new(2026, 12, 17), course: create(:course))
    create(:enrollment, user: user, course: exam.course)

    start_host(McpTools::BusyTimesApp)
    send_tool_result(tool_result(McpTools::MyBusyTimes, user, start_date: "2026-12-16", end_date: "2026-12-18"))

    within_frame("app") do
      expect(page).to have_css("h1", text: "My busy times")
      expect(page).to have_css("#summary", text: "Dec 16 – Dec 18 · 1 busy time")
      expect(page).to have_css(".row", count: 3)
      expect(page).to have_css(".row[data-date='2026-12-16'] .free", text: "Free")
      expect(page).to have_css(".row[data-date='2026-12-17'] .busy", text: "8:00 – 10:00 AM")
      expect(find(".row[data-date='2026-12-17']")["aria-label"]).to eq("Thursday, Dec 17: busy 8:00 – 10:00 AM")
    end

    wait_for_host_message("ui/notifications/size-changed")
  end

  it "names the friend of friend_busy_times" do
    friend = create(:user, first_name: "Morgan")
    friendship = create(:friendship, :accepted, requester: user, addressee: friend)
    friendship.update_visibility_for!(friend, :availability_only)

    start_host(McpTools::BusyTimesApp)
    send_tool_result(tool_result(McpTools::FriendBusyTimes, user,
                                 friend_id: friend.public_id, start_date: "2026-12-16", end_date: "2026-12-16"))

    within_frame("app") do
      expect(page).to have_css("h1", text: "’s busy times")
      expect(page).to have_css(".row .free", text: "Free")
    end
  end
end
