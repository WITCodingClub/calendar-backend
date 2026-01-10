# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseDataSyncJob, type: :job do
  let(:term) { create(:term, :current) }
  let(:course) { create(:course, term: term, title: "Original Title", credit_hours: 3) }
  let(:fresh_data) do
    {
      title: "Updated Title",
      credit_hours: 4,
      grade_mode: "Standard Letter",
      subject: "CS",
      section_number: "001",
      schedule_type: "Lecture (LEC)"
    }
  end

  before do
    allow(Term).to receive(:current_uid).and_return(term.uid)
    allow(Term).to receive(:next_uid).and_return(nil)
  end

  describe "#perform" do
    context "with default term UIDs" do
      it "syncs courses for current term" do
        allow(LeopardWebService).to receive(:get_class_details).and_return(fresh_data)
        
        expect do
          CourseDataSyncJob.new.perform
        end.to change { course.reload.title }.from("Original Title").to("Updated Title")
                                             .and change { course.credit_hours }.from(3).to(4)
      end

      it "handles LeopardWeb API errors gracefully" do
        allow(LeopardWebService).to receive(:get_class_details).and_raise(StandardError, "API Error")
        
        expect(Rails.logger).to receive(:error).with(/Failed to fetch data for CRN/)
        expect { CourseDataSyncJob.new.perform }.not_to raise_error
      end
    end

    context "with specific term UIDs" do
      let(:other_term) { create(:term, uid: 202502) }
      let(:other_course) { create(:course, term: other_term) }

      it "syncs only specified terms" do
        allow(LeopardWebService).to receive(:get_class_details).and_return(fresh_data)
        
        CourseDataSyncJob.new.perform(term_uids: [other_term.uid])
        
        expect(LeopardWebService).to have_received(:get_class_details)
          .with(term: other_term.uid, course_reference_number: other_course.crn)
      end
    end
  end

  describe "#course_data_changed?" do
    let(:job) { CourseDataSyncJob.new }

    it "detects title changes" do
      result = job.send(:course_data_changed?, course, { title: "New Title" })
      expect(result).to be true
    end

    it "detects credit hour changes" do
      result = job.send(:course_data_changed?, course, { credit_hours: 5 })
      expect(result).to be true
    end

    it "detects schedule type changes" do
      result = job.send(:course_data_changed?, course, { schedule_type: "Laboratory (LAB)" })
      expect(result).to be true
    end

    it "returns false when no changes detected" do
      unchanged_data = {
        title: course.title,
        credit_hours: course.credit_hours,
        grade_mode: course.grade_mode,
        subject: course.subject,
        section_number: course.section_number,
        schedule_type: course.schedule_type
      }
      
      result = job.send(:course_data_changed?, course, unchanged_data)
      expect(result).to be false
    end

    it "handles nil values gracefully" do
      result = job.send(:course_data_changed?, course, {})
      expect(result).to be false
    end
  end

  describe "#update_course_from_fresh_data" do
    let(:job) { CourseDataSyncJob.new }

    it "updates all changed course attributes" do
      job.send(:update_course_from_fresh_data, course, fresh_data, term.uid)
      
      course.reload
      expect(course.title).to eq("Updated Title")
      expect(course.credit_hours).to eq(4)
      expect(course.grade_mode).to eq("Standard Letter")
      expect(course.subject).to eq("CS")
      expect(course.section_number).to eq("001")
      expect(course.schedule_type).to eq("LEC")
    end

    it "extracts schedule type from parentheses" do
      data_with_schedule = fresh_data.merge(schedule_type: "Laboratory (LAB)")
      
      job.send(:update_course_from_fresh_data, course, data_with_schedule, term.uid)
      
      expect(course.reload.schedule_type).to eq("LAB")
    end

    it "handles missing attributes gracefully" do
      partial_data = { title: "Partial Update" }

      expect do
        job.send(:update_course_from_fresh_data, course, partial_data, term.uid)
      end.to change { course.reload.title }.to("Partial Update")
    end

    it "preserves roman numerals in course titles" do
      data_with_roman_numerals = { title: "CALCULUS II" }

      job.send(:update_course_from_fresh_data, course, data_with_roman_numerals, term.uid)

      expect(course.reload.title).to eq("Calculus II")
    end

    it "removes spaces between digits and letters in course titles" do
      data_with_spaced_suffix = { title: "CALCULUS 2 A" }

      job.send(:update_course_from_fresh_data, course, data_with_spaced_suffix, term.uid)

      expect(course.reload.title).to eq("Calculus 2A")
    end
  end

  describe "#meeting_times_changed?" do
    let(:job) { CourseDataSyncJob.new }
    let!(:meeting_time) { create(:meeting_time, course: course) }

    it "detects when meeting times have TBD location data" do
      tbd_room = create(:room, number: 0)
      tbd_building = create(:building, abbreviation: "TBD")
      tbd_room.update!(building: tbd_building)
      meeting_time.update!(room: tbd_room)
      
      result = job.send(:meeting_times_changed?, course, {})
      expect(result).to be true
    end

    it "returns false when meeting times have proper location data" do
      proper_room = create(:room, number: 101)
      proper_building = create(:building, abbreviation: "SCI")
      proper_room.update!(building: proper_building)
      meeting_time.update!(room: proper_room)
      
      result = job.send(:meeting_times_changed?, course, {})
      expect(result).to be false
    end
  end

  describe "error handling and rate limiting" do
    let(:job) { CourseDataSyncJob.new }

    it "continues processing after individual course failures" do
      course1 = create(:course, term: term, crn: 12345)
      course2 = create(:course, term: term, crn: 67890)
      
      allow(LeopardWebService).to receive(:get_class_details)
        .with(term: term.uid, course_reference_number: 12345)
        .and_raise(StandardError, "API Error")
      
      allow(LeopardWebService).to receive(:get_class_details)
        .with(term: term.uid, course_reference_number: 67890)
        .and_return(fresh_data)
      
      expect(Rails.logger).to receive(:error).with(/Failed to sync course 12345/)
      expect { job.perform(term_uids: [term.uid]) }.not_to raise_error
    end

    it "implements rate limiting with sleep between API calls" do
      allow(LeopardWebService).to receive(:get_class_details).and_return(fresh_data)
      allow(job).to receive(:sleep)
      
      job.perform(term_uids: [term.uid])
      
      expect(job).to have_received(:sleep).with(0.1).at_least(:once)
    end
  end

  describe "concurrency limits" do
    it "has proper concurrency key to prevent overlapping syncs" do
      job = CourseDataSyncJob.new
      expect(job.class.get_sidekiq_options["limits_concurrency"]["to"]).to eq(1)
      expect(job.class.get_sidekiq_options["limits_concurrency"]["key"].call).to eq("course_data_sync")
    end
  end
end