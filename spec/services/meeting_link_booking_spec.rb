# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingLinkBooking do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)  { Time.zone }
  let(:owner) { create(:user) }
  let(:link)  { create(:meeting_link, user: owner, starts_on: Date.new(2026, 10, 8), ends_on: Date.new(2026, 10, 9), duration_minutes: 30) }
  let(:start) { "2026-10-08T10:00:00-04:00" }

  # Wednesday 2026-10-07, noon.
  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  before { Flipper.enable_actor(FlipperFlags::MEETING_LINKS, owner) }

  after { Flipper.disable(FlipperFlags::MEETING_LINKS) }

  def book(target = link, **overrides)
    described_class.call(link: target, start_time: start, guest_name: "Sample Guest", guest_email: "guest@example.com", **overrides)
  end

  it "makes the meeting in the owner's name with the guest, uses up the link, and sends the email after commit" do
    expect { book }
      .to have_enqueued_job(FriendMeetingPublishJob)
      .and have_enqueued_mail(MeetingLinkMailer, :booked)

    meeting = FriendMeeting.sole
    expect(meeting).to have_attributes(user: owner, title: "Meeting with Sample Guest", guest_name: "Sample Guest",
                                       guest_email: "guest@example.com", start_time: zone.local(2026, 10, 8, 10),
                                       end_time: zone.local(2026, 10, 8, 10, 30))
    expect(link.reload).to have_attributes(used_at: be_present, friend_meeting: meeting, guest_user: nil)
  end

  it "keeps the signed-in guest on the link" do
    guest = create(:user)

    book(guest_user: guest)

    expect(link.reload.guest_user).to eq(guest)
  end

  it "uses the owner's title when the link has one" do
    link.update!(title: "Project check-in")

    book

    expect(FriendMeeting.sole.title).to eq("Project check-in")
  end

  it "refuses a second pick, so a link books one meeting only" do
    book

    expect { book(MeetingLink.find(link.id), guest_email: "other@example.com") }.to raise_error(described_class::Gone)
    expect(FriendMeeting.count).to eq(1)
  end

  it "refuses a revoked or expired link, or one whose owner lost the flag" do
    revoked = create(:meeting_link, :revoked, user: owner)
    expired = create(:meeting_link, :expired, user: owner)

    expect { book(revoked) }.to raise_error(described_class::Gone)
    expect { book(expired) }.to raise_error(described_class::Gone)

    Flipper.disable(FlipperFlags::MEETING_LINKS)
    expect { book }.to raise_error(described_class::Gone)
    expect(FriendMeeting.count).to eq(0)
  end

  it "refuses a time that is not free, and leaves the link usable" do
    course = create(:course)
    create(:course_meeting_time, course: course, day_of_week: :thursday, begin_time: 1000, end_time: 1050)
    create(:enrollment, user: owner, course: course)

    expect { book }.to raise_error(described_class::Invalid, /no longer free/)
    expect(link.reload).to be_usable
  end

  it "refuses a time outside the offered slots" do
    expect { book(start_time: "2026-10-08T10:10:00-04:00") }.to raise_error(described_class::Invalid, /no longer free/)
    expect { book(start_time: "tomorrow") }.to raise_error(described_class::Invalid, "Pick a time.")
  end

  it "needs a name and a valid email" do
    expect { book(guest_name: " ") }.to raise_error(described_class::Invalid, "Enter your name.")
    expect { book(guest_name: "x" * 101) }.to raise_error(described_class::Invalid, /100 characters/)
    expect { book(guest_email: "not-an-email") }.to raise_error(described_class::Invalid, "Enter a valid email address.")
    expect(link.reload).to be_usable
  end
end

# Two guests pick at the same moment. Each thread has its own database
# connection, so this group runs outside the test transaction and removes its
# own rows.
RSpec.describe MeetingLinkBooking, "with two guests at once" do
  self.use_transactional_tests = false

  let!(:owner) { create(:user) }
  let!(:link) do
    create(:meeting_link, user: owner, starts_on: 2.days.from_now.to_date.next_weekday, ends_on: 2.days.from_now.to_date.next_weekday)
  end

  before { Flipper.enable_actor(FlipperFlags::MEETING_LINKS, owner) }

  after do
    Flipper.disable(FlipperFlags::MEETING_LINKS)
    MeetingLink.where(user: owner).delete_all
    FriendMeeting.where(user: owner).destroy_all
    owner.destroy!
  end

  it "books exactly one meeting" do
    slots   = MeetingLinkSlots.new(link).call.first(2)
    ready   = Queue.new
    go      = Queue.new
    results = Queue.new

    threads = slots.each_with_index.map do |slot, index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          described_class.call(link: MeetingLink.find(link.id), start_time: slot.start_time.iso8601,
                               guest_name: "Sample Guest #{index}", guest_email: "guest#{index}@example.com")
          results << :booked
        rescue described_class::Gone
          results << :gone
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    threads.each(&:join)

    expect(Array.new(results.size) { results.pop }).to contain_exactly(:booked, :gone)
    expect(FriendMeeting.where(user: owner).count).to eq(1)
    expect(link.reload.friend_meeting).to be_present
  end
end
