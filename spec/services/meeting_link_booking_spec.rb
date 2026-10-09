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

  before { Flipper.enable_actor(FeatureFlags::MEETING_LINKS, owner) }

  after { Flipper.disable(FeatureFlags::MEETING_LINKS) }

  def book(target = link, **overrides)
    described_class.call(link: target, start_time: start, guest_name: "Sample Guest", guest_email: "guest@example.com", **overrides)
  end

  it "makes the meeting in the owner's name with the guest, uses up the link, and sends the email after commit" do
    create(:course_calendar, oauth_credential: create(:oauth_credential, user: owner))

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

    Flipper.disable(FeatureFlags::MEETING_LINKS)
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

  it "turns a deadlock into a request to pick again, and leaves the link usable" do
    allow(FriendMeetingCreator).to receive(:call).and_raise(ActiveRecord::Deadlocked)

    expect { book }.to raise_error(described_class::Invalid, /Pick your time again/)
    expect(link.reload).to be_usable
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

  before { Flipper.enable_actor(FeatureFlags::MEETING_LINKS, owner) }

  after do
    Flipper.disable(FeatureFlags::MEETING_LINKS)
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

# Two guests pick the same time on two links of the same owner. Each link
# row is its own lock, so only a lock on the owner stops a double booking.
RSpec.describe MeetingLinkBooking, "with two links of one owner at once" do
  self.use_transactional_tests = false

  let!(:owner) { create(:user) }
  let(:day)    { 2.days.from_now.to_date.next_weekday }
  let!(:links) { create_list(:meeting_link, 2, user: owner, starts_on: day, ends_on: day) }

  before { Flipper.enable_actor(FeatureFlags::MEETING_LINKS, owner) }

  after do
    Flipper.disable(FeatureFlags::MEETING_LINKS)
    MeetingLink.where(user: owner).delete_all
    FriendMeeting.where(user: owner).destroy_all
    owner.destroy!
  end

  # Each booking waits after it finds the slot free, so without the owner
  # lock both bookings would see the slot free before either saves.
  def slow_down_slot_checks
    allow(MeetingLinkSlots).to receive(:new).and_wrap_original do |original, *args, **options|
      slots = original.call(*args, **options)
      allow(slots).to receive(:find).and_wrap_original do |find, *find_args|
        found = find.call(*find_args)
        sleep 0.3
        found
      end
      slots
    end
  end

  it "books the slot once and tells the second guest to pick another time" do
    start   = MeetingLinkSlots.new(links.first).call.first.start_time.iso8601
    ready   = Queue.new
    go      = Queue.new
    results = Queue.new
    slow_down_slot_checks

    threads = links.each_with_index.map do |link, index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          described_class.call(link: MeetingLink.find(link.id), start_time: start,
                               guest_name: "Sample Guest #{index}", guest_email: "guest#{index}@example.com")
          results << :booked
        rescue described_class::Invalid
          results << :taken
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    threads.each(&:join)

    expect(Array.new(results.size) { results.pop }).to contain_exactly(:booked, :taken)
    expect(FriendMeeting.where(user: owner).count).to eq(1)
  end
end

# Two signed-in people book each other's links at the same moment. Saving the
# link takes a key share lock on the guest's user row (the foreign key), so
# a booking that locked only its owner could deadlock with the other one.
RSpec.describe MeetingLinkBooking, "with two people booking each other at once" do
  self.use_transactional_tests = false

  let!(:first_person)  { create(:user) }
  let!(:second_person) { create(:user) }
  let(:day)            { 2.days.from_now.to_date.next_weekday }
  let!(:first_link)    { create(:meeting_link, user: first_person, starts_on: day, ends_on: day) }
  let!(:second_link)   { create(:meeting_link, user: second_person, starts_on: day, ends_on: day) }

  before { [ first_person, second_person ].each { |person| Flipper.enable_actor(FeatureFlags::MEETING_LINKS, person) } }

  after do
    Flipper.disable(FeatureFlags::MEETING_LINKS)
    people = [ first_person, second_person ]
    MeetingLink.where(user: people).delete_all
    FriendMeeting.where(user: people).destroy_all
    people.each(&:destroy!)
  end

  def slow_down_slot_checks
    allow(MeetingLinkSlots).to receive(:new).and_wrap_original do |original, *args, **options|
      slots = original.call(*args, **options)
      allow(slots).to receive(:find).and_wrap_original do |find, *find_args|
        found = find.call(*find_args)
        sleep 0.3
        found
      end
      slots
    end
  end

  it "books both without a deadlock" do
    slots   = MeetingLinkSlots.new(first_link).call
    ready   = Queue.new
    go      = Queue.new
    results = Queue.new
    slow_down_slot_checks

    bookings = [ [ second_link, first_person, slots.first ], [ first_link, second_person, slots.last ] ]
    threads  = bookings.each_with_index.map do |(link, guest, slot), index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          described_class.call(link: MeetingLink.find(link.id), start_time: slot.start_time.iso8601, guest_user: guest,
                               guest_name: "Sample Guest #{index}", guest_email: "guest#{index}@example.com")
          results << :booked
        rescue StandardError => e
          results << e.class
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    threads.each(&:join)

    expect(Array.new(results.size) { results.pop }).to eq(%i[booked booked])
  end
end
