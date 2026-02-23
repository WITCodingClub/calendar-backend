# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transfer::EquivalencySyncService do
  describe ".call" do
    let(:service) { described_class.new }

    # Sample TES page HTML with an equivalency grid
    let(:tes_html_with_grid) do
      <<~HTML
        <html>
        <body>
          <table id="gdvCourseEQ">
            <tr>
              <th>Select</th>
              <th>Sending Institution / Course</th>
              <th>Receiving Course</th>
              <th>Dates</th>
            </tr>
            <tr>
              <td><input type="checkbox" /></td>
              <td>
                <b>Boston University</b>
                <br/>CS 111
                <br/>Intro to CS
                <br/>3.0 credits
              </td>
              <td>
                <br/>COMP 1000
                <br/>Computer Science I
              </td>
              <td>01/15/2024</td>
            </tr>
            <tr>
              <td><input type="checkbox" /></td>
              <td>
                <b>Northeastern University</b>
                <br/>CS 2500
                <br/>Fundamentals of CS
                <br/>4.0 credits
              </td>
              <td>
                <br/>COMP 2000
                <br/>Computer Science II
              </td>
              <td>09/01/2023</td>
            </tr>
          </table>
        </body>
        </html>
      HTML
    end

    let(:tes_html_empty) do
      <<~HTML
        <html>
        <body>
          <span id="lblPubViewHeader">
            <b>This page is not available.</b>
          </span>
        </body>
        </html>
      HTML
    end

    before do
      stub_request(:get, /tes\.collegesource\.com/)
        .to_return(status: 200, body: tes_html_with_grid)
    end

    context "when TES page has equivalency grid" do
      let!(:wit_course_1) do
        create(:course, subject: "Computer Science (COMP)", course_number: 1000)
      end

      let!(:wit_course_2) do
        create(:course, subject: "Computer Science (COMP)", course_number: 2000)
      end

      it "returns result hash with sync counts" do
        result = described_class.call

        expect(result).to include(
          universities_synced: a_value >= 0,
          courses_synced: a_value >= 0,
          equivalencies_synced: a_value >= 0,
          errors: an_instance_of(Array)
        )
      end

      it "creates university records" do
        expect { described_class.call }.to change(Transfer::University, :count).by(2)
      end

      it "creates transfer course records" do
        expect { described_class.call }.to change(Transfer::Course, :count).by(2)
      end

      it "creates equivalency records linking to WIT courses" do
        expect { described_class.call }.to change(Transfer::Equivalency, :count).by(2)
      end

      it "does not create duplicate records on re-run" do
        described_class.call
        expect { described_class.call }.not_to change(Transfer::University, :count)
        expect { described_class.call }.not_to change(Transfer::Course, :count)
        expect { described_class.call }.not_to change(Transfer::Equivalency, :count)
      end
    end

    context "when WIT course is not found" do
      it "records error for missing WIT course" do
        result = described_class.call

        expect(result[:errors]).to include(a_string_matching(/WIT course not found/))
      end

      it "does not create equivalency without WIT course" do
        expect { described_class.call }.not_to change(Transfer::Equivalency, :count)
      end
    end

    context "when TES page has no grid" do
      before do
        stub_request(:get, /tes\.collegesource\.com/)
          .to_return(status: 200, body: tes_html_empty)
        # Also stub the POST for postback attempt
        stub_request(:post, /tes\.collegesource\.com/)
          .to_return(status: 200, body: tes_html_empty)
      end

      it "returns empty results with an error" do
        result = described_class.call

        expect(result[:equivalencies_synced]).to eq(0)
        expect(result[:errors]).to include(a_string_matching(/No equivalency data found/))
      end
    end

    context "when network error occurs" do
      before do
        stub_request(:get, /tes\.collegesource\.com/)
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
      end

      it "handles network errors gracefully" do
        result = described_class.call

        expect(result[:errors]).to include(a_string_matching(/Network error/))
        expect(result[:equivalencies_synced]).to eq(0)
      end
    end

    context "when TES returns non-200 status" do
      before do
        stub_request(:get, /tes\.collegesource\.com/)
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "handles HTTP errors gracefully" do
        result = described_class.call

        expect(result[:errors]).to include(a_string_matching(/error/i))
      end
    end
  end

  describe "#find_wit_course (private)" do
    let(:service) { described_class.new }

    let!(:comp_course) do
      create(:course, subject: "Computer Science (COMP)", course_number: 1000)
    end

    it "finds course by subject abbreviation and number" do
      result = service.send(:find_wit_course, "COMP 1000")
      expect(result).to eq(comp_course)
    end

    it "finds course without space in code" do
      result = service.send(:find_wit_course, "COMP1000")
      expect(result).to eq(comp_course)
    end

    it "returns nil for unknown course" do
      result = service.send(:find_wit_course, "UNKN 9999")
      expect(result).to be_nil
    end

    it "returns nil for blank input" do
      result = service.send(:find_wit_course, "")
      expect(result).to be_nil
    end
  end

  describe "#generate_university_code (private)" do
    let(:service) { described_class.new }

    it "generates code from university name" do
      code = service.send(:generate_university_code, "Boston University")
      expect(code).to be_present
      expect(code).to match(/\A[A-Z-]+\z/)
    end

    it "generates different codes for different universities" do
      code1 = service.send(:generate_university_code, "Boston University")
      code2 = service.send(:generate_university_code, "Northeastern University")
      expect(code1).not_to eq(code2)
    end
  end
end
