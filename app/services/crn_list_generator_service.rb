# frozen_string_literal: true

class CrnListGeneratorService < ApplicationService
  def initialize(user:, term:)
    @user = user
    @term = term
    super()
  end

  def call
    planned = @user.course_plans
                   .where(term: @term)
                   .where(status: %w[planned enrolled])
                   .includes(course: [:meeting_times, :faculties])

    planned_entries = build_planned_entries(planned)
    planned_entries = detect_conflicts(planned_entries)

    {
      term: {
        pub_id: @term.public_id,
        uid: @term.uid,
        name: @term.name
      },
      courses: planned_entries,
      summary: build_summary(planned_entries)
    }
  end

  private

  def build_planned_entries(planned_course_plans)
    planned_course_plans.map do |plan|
      course = plan.course

      if course.nil?
        {
          type: "planned",
          planned_subject: plan.planned_subject,
          planned_course_number: plan.planned_course_number,
          crn: plan.planned_crn,
          status: plan.status,
          course: nil,
          meeting_times: [],
          conflict: false
        }
      else
        entry = build_course_entry(course)
        entry.merge(
          type: "planned",
          status: plan.status,
          notes: plan.notes
        )
      end
    end
  end

  def build_course_entry(course)
    faculty = course.faculties.first

    {
      course_id: course.public_id,
      crn: course.crn,
      title: course.title,
      subject: course.subject,
      course_number: course.course_number,
      section_number: course.section_number,
      credit_hours: course.credit_hours,
      schedule_type: course.schedule_type,
      faculty: if faculty
                 {
                   pub_id: faculty.public_id,
                   name: "#{faculty.first_name} #{faculty.last_name}"
                 }
               else
                 nil
               end,
      meeting_times: course.meeting_times.map { |mt| format_meeting_time(mt) },
      conflict: false
    }
  end

  def format_meeting_time(mt)
    {
      day: mt.day_of_week,
      begin_time: mt.fmt_begin_time_military,
      end_time: mt.fmt_end_time_military,
      begin_time_int: mt.begin_time,
      end_time_int: mt.end_time,
      location: mt.building_room
    }
  end

  def detect_conflicts(entries)
    all_times = entries.flat_map.with_index do |entry, idx|
      entry[:meeting_times].map { |mt| mt.merge(entry_index: idx) }
    end

    (0...all_times.size).each do |i|
      ((i + 1)...all_times.size).each do |j|
        a = all_times[i]
        b = all_times[j]
        next if a[:entry_index] == b[:entry_index]
        next if a[:day] != b[:day]

        next unless times_overlap?(a[:begin_time_int], a[:end_time_int],
                                   b[:begin_time_int], b[:end_time_int])

        entries[a[:entry_index]][:conflict] = true
        entries[b[:entry_index]][:conflict] = true
      end
    end

    entries
  end

  def times_overlap?(start1, end1, start2, end2)
    start1 < end2 && start2 < end1
  end

  def build_summary(entries)
    total_credits = entries.sum { |e| e[:credit_hours] || 0 }
    all_crns = entries.filter_map { |e| e[:crn] }.uniq

    {
      total_planned: entries.size,
      total_credits: total_credits,
      has_conflicts: entries.any? { |e| e[:conflict] },
      crn_list: all_crns.join(", ")
    }
  end

end
