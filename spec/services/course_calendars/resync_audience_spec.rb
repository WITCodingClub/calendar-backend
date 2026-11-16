# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::ResyncAudience do
  def user_with_calendar(provider: "google", **config)
    create(:user).tap do |user|
      create(:course_calendar, oauth_credential: create(:oauth_credential, user: user, provider: provider))
      user.user_extension_config.update!(**config) if config.any?
    end
  end

  it "takes every user with a course calendar, on any provider" do
    google    = user_with_calendar
    microsoft = user_with_calendar(provider: "microsoft")
    create(:user)

    expect(described_class.all).to contain_exactly(google, microsoft)
  end

  it "narrows to the users enrolled in a term" do
    term     = create(:term)
    enrolled  = user_with_calendar
    microsoft = user_with_calendar(provider: "microsoft")
    [ enrolled, microsoft ].each { |user| create(:enrollment, user: user, course: create(:course, term: term)) }
    user_with_calendar

    # Finals reach Microsoft calendars too, not only Google ones.
    expect(described_class.enrolled_in(term.id)).to contain_exactly(enrolled, microsoft)
  end

  it "narrows to the users who show university events" do
    opted_in = user_with_calendar(sync_university_events: true)
    user_with_calendar(sync_university_events: false)

    expect(described_class.with_university_events).to contain_exactly(opted_in)
  end
end
