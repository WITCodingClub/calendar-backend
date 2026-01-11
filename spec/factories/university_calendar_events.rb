# frozen_string_literal: true

# == Schema Information
#
# Table name: university_calendar_events
# Database name: primary
#
#  id              :bigint           not null, primary key
#  academic_term   :string
#  all_day         :boolean          default(FALSE), not null
#  category        :string
#  description     :text
#  end_time        :datetime         not null
#  event_type_raw  :string
#  ics_uid         :string           not null
#  last_fetched_at :datetime
#  location        :string
#  organization    :string
#  recurrence      :text
#  source_url      :string
#  start_time      :datetime         not null
#  summary         :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#
# Indexes
#
#  index_university_calendar_events_on_academic_term            (academic_term)
#  index_university_calendar_events_on_category                 (category)
#  index_university_calendar_events_on_ics_uid                  (ics_uid) UNIQUE
#  index_university_calendar_events_on_start_time               (start_time)
#  index_university_calendar_events_on_start_time_and_end_time  (start_time,end_time)
#  index_university_calendar_events_on_term_id                  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
FactoryBot.define do
  factory :university_calendar_event do
    sequence(:ics_uid) { |n| "event-uid-#{n}@university.edu" }
    summary { "University Event" }
    description { "A university calendar event" }
    location { nil }
    start_time { 1.week.from_now.beginning_of_day }
    end_time { 1.week.from_now.end_of_day }
    all_day { true }
    recurrence { nil }
    category { "campus_event" }
    organization { nil }
    academic_term { nil }
    event_type_raw { nil }
    term { nil }
    last_fetched_at { Time.current }
    source_url { "https://25livepub.collegenet.com/calendars/wit-main-events-calendar.ics" }

    trait :holiday do
      summary { "Thanksgiving Break - No Classes" }
      category { "holiday" }
      all_day { true }
    end

    trait :spring_break do
      summary { "Spring Break - No Classes" }
      category { "holiday" }
      all_day { true }
      start_time { Date.new(2025, 3, 10).beginning_of_day }
      end_time { Date.new(2025, 3, 14).end_of_day }
    end

    # Term dates category - semester start/end
    trait :term_dates do
      summary { "Fall 2025 Classes Begin" }
      category { "term_dates" }
      academic_term { "Fall" }
      all_day { true }
    end

    trait :classes_begin do
      summary { "Fall 2025 Classes Begin" }
      category { "term_dates" }
      academic_term { "Fall" }
      all_day { true }
    end

    trait :classes_end do
      summary { "Fall 2025 Classes End" }
      category { "term_dates" }
      academic_term { "Fall" }
      all_day { true }
    end

    # Registration category
    trait :registration do
      summary { "Registration Opens" }
      category { "registration" }
      all_day { true }
    end

    # Deadline category
    trait :deadline do
      summary { "Withdrawal Deadline" }
      category { "deadline" }
      all_day { true }
    end

    # Finals category
    trait :finals do
      summary { "Final Exams Begin" }
      category { "finals" }
      all_day { true }
    end

    # Graduation category
    trait :graduation do
      summary { "Commencement Ceremony" }
      category { "graduation" }
      all_day { false }
      start_time { 1.month.from_now.change(hour: 10) }
      end_time { 1.month.from_now.change(hour: 14) }
      location { "Main Campus Quad" }
    end

    # Alias for backwards compatibility
    trait :commencement do
      summary { "Commencement Ceremony" }
      category { "graduation" }
      all_day { false }
      start_time { 1.month.from_now.change(hour: 10) }
      end_time { 1.month.from_now.change(hour: 14) }
      location { "Main Campus Quad" }
    end

    # Academic category - catch-all for misc academic events
    trait :academic do
      summary { "Academic Calendar Announcement" }
      category { "academic" }
      event_type_raw { "Calendar Announcement" }
      all_day { true }
    end

    trait :campus_event do
      summary { "Campus Tour" }
      category { "campus_event" }
      all_day { false }
      start_time { 1.day.from_now.change(hour: 14) }
      end_time { 1.day.from_now.change(hour: 16) }
      organization { "Admissions Office" }
    end

    trait :meeting do
      summary { "Board of Trustees Meeting" }
      category { "meeting" }
      all_day { false }
      event_type_raw { "Meeting" }
    end

    trait :exhibit do
      summary { "Student Art Showcase" }
      category { "exhibit" }
      all_day { false }
      event_type_raw { "Exhibit" }
    end

    trait :past do
      start_time { 1.week.ago.beginning_of_day }
      end_time { 1.week.ago.end_of_day }
    end

    trait :with_term do
      term
      academic_term { term.season.to_s.capitalize }
    end

    trait :recurring do
      recurrence { ["RRULE:FREQ=WEEKLY;COUNT=10"] }
    end
  end
end
