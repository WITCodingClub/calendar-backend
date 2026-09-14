# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateMyProfessorService, type: :service do
  subject(:service) { described_class.new }

  let(:base_url) { RateMyProfessorService::BASE_URL }

  def stub_graphql(operation_name, status: 200, body: nil, fixture: nil)
    response_body = body || file_fixture("rate_my_professor/#{fixture}").read

    stub_request(:post, base_url)
      .with(body: hash_including("operationName" => operation_name))
      .to_return(status: status, body: response_body, headers: { "Content-Type" => "application/json" })
  end

  describe "#search_professors" do
    it "returns the matching teachers for a name search" do
      stub_graphql("NewSearchTeachersQuery", fixture: "search_results.json")

      result = service.search_professors("Ada Byron")
      teacher = result.dig("data", "newSearch", "teachers", "edges").first["node"]

      expect(teacher["firstName"]).to eq("Ada")
      expect(teacher["lastName"]).to eq("Byron")
      expect(teacher["id"]).to eq("VGVhY2hlci0xMjM0NTY=")
    end

    it "sends the search text and school in the GraphQL variables" do
      stub_graphql("NewSearchTeachersQuery", fixture: "search_results.json")

      service.search_professors("Ada Byron", school_id: "custom-school", count: 5)

      expect(WebMock).to have_requested(:post, base_url).with { |req|
        payload = JSON.parse(req.body)
        payload["variables"]["query"]["text"] == "Ada Byron" &&
          payload["variables"]["query"]["schoolID"] == "custom-school" &&
          payload["variables"]["count"] == 5
      }
    end

    it "returns an empty edge list when nobody matches" do
      stub_graphql("NewSearchTeachersQuery", fixture: "search_empty.json")

      result = service.search_professors("Nobody Real")

      expect(result.dig("data", "newSearch", "teachers", "edges")).to eq([])
    end

    it "returns the raw response body when the server answers with an error status" do
      stub_graphql("NewSearchTeachersQuery", status: 500, body: { error: "boom" }.to_json)

      result = service.search_professors("Ada Byron")

      expect(result).to eq("error" => "boom")
    end

    it "raises when the response body is not valid JSON" do
      stub_graphql("NewSearchTeachersQuery", status: 200, body: "<html>not json</html>")

      expect { service.search_professors("Ada Byron") }.to raise_error(Faraday::ParsingError)
    end

    it "raises when the request times out" do
      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "NewSearchTeachersQuery"))
        .to_timeout

      expect { service.search_professors("Ada Byron") }.to raise_error(Faraday::ConnectionFailed)
    end
  end

  describe "#get_teacher_details" do
    it "returns the teacher node for a known id" do
      stub_graphql("TeacherRatingsPageQuery", fixture: "teacher_details.json")

      result = service.get_teacher_details("VGVhY2hlci0xMjM0NTY=")
      teacher = result.dig("data", "node")

      expect(teacher["firstName"]).to eq("Ada")
      expect(teacher["teacherRatingTags"].map { |t| t["tagName"] }).to eq([ "Caring", "Tough Grader" ])
      expect(teacher["relatedTeachers"].first["firstName"]).to eq("Grace")
    end

    it "returns a nil node when the teacher id does not resolve" do
      stub_graphql("TeacherRatingsPageQuery", body: { data: { node: nil } }.to_json)

      result = service.get_teacher_details("unknown-id")

      expect(result.dig("data", "node")).to be_nil
    end
  end

  describe "#get_ratings" do
    it "returns one page of ratings" do
      stub_graphql("RatingsListQuery", fixture: "ratings_page1.json")

      result = service.get_ratings("VGVhY2hlci0xMjM0NTY=")
      edges = result.dig("data", "node", "ratings", "edges")

      expect(edges.size).to eq(1)
      expect(edges.first["node"]["comment"]).to eq("Fake review one, purely synthetic test data.")
    end
  end

  describe "#get_all_ratings" do
    it "walks every page and concatenates the rating nodes" do
      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "RatingsListQuery", "variables" => hash_including("cursor" => nil)))
        .to_return(status: 200, body: file_fixture("rate_my_professor/ratings_page1.json").read,
                   headers: { "Content-Type" => "application/json" })

      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "RatingsListQuery", "variables" => hash_including("cursor" => "cursor-1")))
        .to_return(status: 200, body: file_fixture("rate_my_professor/ratings_page2.json").read,
                   headers: { "Content-Type" => "application/json" })

      all_ratings = service.get_all_ratings("VGVhY2hlci0xMjM0NTY=")

      expect(all_ratings.map { |r| r["legacyId"] }).to eq([ 1, 2 ])
    end

    it "returns an empty array when there are no ratings" do
      stub_graphql("RatingsListQuery", fixture: "ratings_empty.json")

      expect(service.get_all_ratings("VGVhY2hlci0xMjM0NTY=")).to eq([])
    end

    it "stops without raising when the node is missing from the response" do
      stub_graphql("RatingsListQuery", body: { data: { node: nil } }.to_json)

      expect(service.get_all_ratings("unknown-id")).to eq([])
    end
  end

  describe "#add_professor_url" do
    it "returns the RateMyProfessors add-a-professor page" do
      expect(service.add_professor_url).to eq("https://www.ratemyprofessors.com/add/professor")
    end
  end

  describe "#faculty_directory_url" do
    it "builds a WIT faculty directory search link from a name" do
      url = service.faculty_directory_url(first_name: "Ada", last_name: "Byron")

      expect(url).to eq(
        "https://wit.edu/faculty-staff-directory?search=Ada+Byron&dept=&school=&employee_type=All"
      )
    end

    it "URL-encodes names with special characters" do
      url = service.faculty_directory_url(first_name: "Jean-Luc", last_name: "O'Reilly")

      expect(url).to include(URI.encode_www_form_component("Jean-Luc"))
      expect(url).to include(URI.encode_www_form_component("O'Reilly"))
    end
  end
end
