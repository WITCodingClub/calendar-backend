# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ICS calendar feed colors", type: :request do
  let(:user) { create(:user) }
  let(:course) { create(:course) }
  let!(:meeting_time) { create(:course_meeting_time, course: course) }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    create(:enrollment, user: user, course: course)
  end

  def event_lines
    get "/calendar/#{user.calendar_token}.ics"
    response.body.split("\r\n").grep(/COLOR/)
  end

  it "gives a class the custom color the user chose" do
    create(:event_preference, user: user, preferenceable: meeting_time, color_id: "#1a2b3c")

    expect(event_lines).to contain_exactly("COLOR:#1a2b3c", "X-APPLE-CALENDAR-COLOR:#1a2b3c")
  end

  it "gives a class without a color preference the default color of its schedule type" do
    user.user_extension_config.update!(default_color_lecture: "#abcdef")

    expect(event_lines).to contain_exactly("COLOR:#abcdef", "X-APPLE-CALENDAR-COLOR:#abcdef")
  end
end
