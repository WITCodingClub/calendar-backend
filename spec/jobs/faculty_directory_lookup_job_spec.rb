# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe FacultyDirectoryLookupJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let!(:faculty) do
      create(:faculty,
             email: "smithj@wit.edu",
             first_name: "J",
             last_name: "Smith",
             directory_last_synced_at: nil)
    end

    context "when faculty is found in directory" do
      let(:search_result) do
        {
          success: true,
          faculty: [
            {
              display_name: "John Smith",
              email: "smithj@wit.edu",
              title: "Professor, Computer Science",
              phone: "617-989-1234",
              office_location: "Beatty 301",
              department: "Computer Science",
              school: "School of Computing & Data Science",
              photo_url: "https://wit.edu/photos/smith.jpg"
            }
          ],
          total_count: 1
        }
      end

      before do
        allow_any_instance_of(FacultyDirectoryService).to receive(:call).and_return(search_result)
        # Stub photo downloads
        stub_request(:get, /https:\/\/wit\.edu\/photos\/.*/)
          .to_return(status: 200, body: "", headers: { "Content-Type" => "image/jpeg" })
      end

      it "updates the faculty record with directory data" do
        described_class.new.perform(faculty.id)

        faculty.reload
        expect(faculty.first_name).to eq("John")
        expect(faculty.last_name).to eq("Smith")
        expect(faculty.title).to eq("Professor, Computer Science")
        expect(faculty.phone).to eq("617-989-1234")
        expect(faculty.office_location).to eq("Beatty 301")
        expect(faculty.directory_last_synced_at).to be_present
      end

      it "sets employee_type based on title" do
        described_class.new.perform(faculty.id)

        faculty.reload
        expect(faculty.employee_type).to eq("faculty")
      end
    end

    context "when faculty is not found in directory" do
      let(:search_result) do
        {
          success: true,
          faculty: [
            { display_name: "Other Person", email: "other@wit.edu", title: "Staff" }
          ],
          total_count: 1
        }
      end

      before do
        allow_any_instance_of(FacultyDirectoryService).to receive(:call).and_return(search_result)
      end

      it "marks as synced to avoid repeated lookups" do
        described_class.new.perform(faculty.id)

        faculty.reload
        expect(faculty.directory_last_synced_at).to be_present
        expect(faculty.title).to be_nil # Original data unchanged
      end
    end

    context "when faculty was recently synced" do
      before do
        faculty.update!(directory_last_synced_at: 1.hour.ago)
      end

      it "skips the lookup" do
        expect_any_instance_of(FacultyDirectoryService).not_to receive(:call)

        described_class.new.perform(faculty.id)
      end
    end

    context "when faculty does not exist" do
      it "returns early without error" do
        expect { described_class.new.perform(99999) }.not_to raise_error
      end
    end

    context "when service fails" do
      before do
        allow_any_instance_of(FacultyDirectoryService).to receive(:call).and_return({
                                                                                      success: false,
                                                                                      error: "Network error",
                                                                                      faculty: [],
                                                                                      total_count: 0
                                                                                    })
      end

      it "does not update the faculty" do
        described_class.new.perform(faculty.id)

        faculty.reload
        expect(faculty.directory_last_synced_at).to be_nil
        expect(faculty.title).to be_nil
      end
    end
  end
end
