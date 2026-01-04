# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe FacultyDirectorySyncJob, type: :job do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:mock_faculty_data) do
      {
        success: true,
        faculty: [
          {
            display_name: "John Smith",
            email: "smithj@wit.edu",
            title: "Professor",
            phone: "617-989-1234",
            office_location: "Beatty 301",
            department: "Computer Science",
            school: "Computing & Data Science",
            photo_url: "https://wit.edu/photos/smith.jpg",
            raw_html: "<div>...</div>"
          }
        ],
        total_count: 1
      }
    end

    before do
      allow(FacultyDirectoryService).to receive(:call).and_return(mock_faculty_data)
      # Stub photo downloads
      stub_request(:get, /https:\/\/wit\.edu\/photos\/.*/)
        .to_return(status: 200, body: "", headers: { "Content-Type" => "image/jpeg" })
    end

    it "creates new faculty records" do
      expect { described_class.new.perform }.to change(Faculty, :count).by(1)

      faculty = Faculty.find_by(email: "smithj@wit.edu")
      expect(faculty.first_name).to eq("John")
      expect(faculty.last_name).to eq("Smith")
      expect(faculty.title).to eq("Professor")
      expect(faculty.phone).to eq("617-989-1234")
      expect(faculty.office_location).to eq("Beatty 301")
      expect(faculty.directory_last_synced_at).to be_present
    end

    it "updates existing faculty records" do
      existing = create(:faculty,
                        email: "smithj@wit.edu",
                        first_name: "J",
                        last_name: "Smith",
                        title: nil)

      expect { described_class.new.perform }.not_to change(Faculty, :count)

      existing.reload
      expect(existing.first_name).to eq("John")
      expect(existing.title).to eq("Professor")
      expect(existing.directory_last_synced_at).to be_present
    end

    it "returns stats" do
      stats = described_class.new.perform

      expect(stats[:created]).to eq(1)
      expect(stats[:updated]).to eq(0)
      expect(stats[:errors]).to be_empty
    end

    context "with middle names" do
      let(:mock_faculty_data) do
        {
          success: true,
          faculty: [
            { display_name: "Mark John Isola", email: "isolam@wit.edu", title: "Professor" }
          ],
          total_count: 1
        }
      end

      it "parses middle names correctly" do
        described_class.new.perform

        faculty = Faculty.find_by(email: "isolam@wit.edu")
        expect(faculty.first_name).to eq("Mark")
        expect(faculty.middle_name).to eq("John")
        expect(faculty.last_name).to eq("Isola")
        expect(faculty.display_name).to eq("Mark John Isola")
      end
    end

    context "when employee type is detected" do
      let(:mock_faculty_data) do
        {
          success: true,
          faculty: [
            { display_name: "Jane Prof", email: "profj@wit.edu", title: "Associate Professor" },
            { display_name: "Bob Staff", email: "staffb@wit.edu", title: "Director, IT" }
          ],
          total_count: 2
        }
      end

      it "correctly identifies faculty vs staff" do
        described_class.new.perform

        prof = Faculty.find_by(email: "profj@wit.edu")
        expect(prof.employee_type).to eq("faculty")

        staff = Faculty.find_by(email: "staffb@wit.edu")
        expect(staff.employee_type).to eq("staff")
      end
    end

    context "when service fails" do
      before do
        allow(FacultyDirectoryService).to receive(:call).and_return({
                                                                      success: false,
                                                                      error: "Network error",
                                                                      faculty: [],
                                                                      total_count: 0
                                                                    })
      end

      it "raises an error" do
        expect { described_class.new.perform }.to raise_error(/Failed to fetch faculty directory/)
      end
    end

    context "with invalid faculty data" do
      let(:mock_faculty_data) do
        {
          success: true,
          faculty: [
            { display_name: "Valid Person", email: "valid@wit.edu", title: "Professor" },
            { display_name: "No Email", email: nil, title: "Staff" },
            { display_name: "", email: "nofirst@wit.edu", title: "Staff" }
          ],
          total_count: 3
        }
      end

      it "skips invalid records and continues" do
        expect { described_class.new.perform }.to change(Faculty, :count).by(1)

        expect(Faculty.find_by(email: "valid@wit.edu")).to be_present
        expect(Faculty.find_by(email: "nofirst@wit.edu")).to be_nil
      end
    end
  end
end
