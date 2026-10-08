# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarSyncMarker do
  let(:course) { create(:course) }
  let(:user) { create(:user) }

  before do
    create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))
    create(:enrollment, user: user, course: course, term: course.term)
  end

  describe ".mark" do
    it "marks the enrolled users with a calendar now outside a batch" do
      described_class.mark(course.id)

      expect(user.reload.calendar_needs_sync).to be(true)
    end

    it "skips enrolled users with no calendar" do
      other = create(:user)
      create(:enrollment, user: other, course: course, term: course.term)

      described_class.mark(course.id)

      expect(other.reload.calendar_needs_sync).to be(false)
    end
  end

  describe ".batch" do
    it "marks the users of every course in one query when the block ends" do
      second = create(:course)
      classmate = create(:user)
      create(:course_calendar, oauth_credential: create(:oauth_credential, user: classmate))
      create(:enrollment, user: classmate, course: second, term: second.term)

      described_class.batch do
        described_class.mark(course.id)
        described_class.mark(second.id)

        expect(user.reload.calendar_needs_sync).to be(false)
      end

      expect([ user, classmate ].map { |u| u.reload.calendar_needs_sync }).to eq([ true, true ])
    end

    it "keeps the outer batch open when a batch is nested" do
      described_class.batch do
        described_class.batch { described_class.mark(course.id) }

        expect(user.reload.calendar_needs_sync).to be(false)
      end

      expect(user.reload.calendar_needs_sync).to be(true)
    end

    it "marks the collected courses when the block raises" do
      expect {
        described_class.batch do
          described_class.mark(course.id)
          raise ArgumentError
        end
      }.to raise_error(ArgumentError)

      expect(user.reload.calendar_needs_sync).to be(true)
    end
  end
end
