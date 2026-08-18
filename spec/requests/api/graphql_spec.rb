# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Graphql", type: :request do
  include_context "catalog fixtures"

  def json = JSON.parse(response.body)

  # Real clients POST JSON, so booleans and numbers keep their types. A
  # form-encoded post would turn every variable into a string.
  def gql(query, variables: nil)
    post "/api/graphql", params: { query: query, variables: variables }, as: :json
    json
  end

  describe "sections" do
    let(:query) do
      <<~GQL
        query($filter: SectionFilterInput) {
          sections(filter: $filter, first: 50) {
            totalCount
            nodes { crn courseCode title creditHours status }
          }
        }
      GQL
    end

    it "returns active sections with a total count" do
      result = gql(query)

      expect(response).to have_http_status(:ok)
      expect(result["errors"]).to be_nil
      expect(result["data"]["sections"]["totalCount"]).to eq(4)
      expect(result["data"]["sections"]["nodes"].map { |n| n["crn"] })
        .to eq([ 10_001, 10_002, 10_003, 20_001 ])
    end

    it "applies the same filters as the REST surface" do
      result = gql(query, variables: { filter: { subject: [ "COMP" ], meetsOn: [ "FRIDAY" ] } })

      expect(result["data"]["sections"]["nodes"].map { |n| n["crn"] }).to eq([ 10_001, 10_003 ])
    end

    it "agrees with REST on the count for the same filters" do
      result = gql(query, variables: { filter: { freeDays: [ "FRIDAY" ], beginsAfter: "10:00" } })
      get "/api/v1/catalog/sections", params: { free_days: "friday", begins_after: "10:00" }

      expect(result["data"]["sections"]["totalCount"]).to eq(json["meta"]["total_count"])
    end

    it "paginates with Relay cursors" do
      result = gql(<<~GQL)
        { sections(first: 2) {
            totalCount
            pageInfo { hasNextPage }
            nodes { crn }
        } }
      GQL

      expect(result["data"]["sections"]["totalCount"]).to eq(4)
      expect(result["data"]["sections"]["nodes"].size).to eq(2)
      expect(result["data"]["sections"]["pageInfo"]["hasNextPage"]).to be(true)
    end

    it "includes cancelled sections only when asked" do
      result = gql(query, variables: { filter: { includeCancelled: true } })

      expect(result["data"]["sections"]["totalCount"]).to eq(5)
    end
  end

  describe "nested section data" do
    it "resolves meeting times, location, instructors, and the final exam" do
      result = gql(<<~GQL)
        { section(crn: 10001) {
            crn
            subjectCode
            term { uid name }
            meetingTimes {
              day beginTime endTime durationMinutes
              location { display building { abbreviation } rooms { number floor } }
            }
            instructors { name rmp { avgRating numRatings wouldTakeAgainPercent } }
            finalExam { date location }
        } }
      GQL

      section = result["data"]["section"]
      expect(result["errors"]).to be_nil
      expect(section["subjectCode"]).to eq("COMP")
      expect(section["term"]).to eq("uid" => 202_710, "name" => "Fall 2026")
      expect(section["meetingTimes"].map { |m| m["day"] }).to eq(%w[MONDAY FRIDAY])
      expect(section["meetingTimes"].first["durationMinutes"]).to eq(75)
      expect(section["meetingTimes"].first["location"]["building"]["abbreviation"]).to eq("ANNX")
      expect(section["instructors"].first["rmp"]["avgRating"]).to eq(4.5)
      expect(section["finalExam"]).to eq("date" => "2026-12-17", "location" => "ANNX 306")
    end

    it "describes location the same way the REST surface does" do
      result = gql("{ section(crn: 10001) { meetingTimes { location { display } } } }")
      get "/api/v1/catalog/sections/10001"

      expect(result["data"]["section"]["meetingTimes"].first["location"]["display"])
        .to eq(json["data"]["meeting_times"].first["location"]["display"])
    end

    it "returns a null location when no room is assigned" do
      result = gql("{ section(crn: 10002) { meetingTimes { location { display } } } }")

      expect(result["data"]["section"]["meetingTimes"].first["location"]).to be_nil
    end

    it "returns a null display for a placeholder TBD building" do
      tbd  = Building.create!(abbreviation: "TBD", name: "To Be Determined")
      room = Room.create!(building: tbd, number: "TBD")
      comp2000.meeting_times.first.rooms << room

      result = gql("{ section(crn: 10002) { meetingTimes { location { display building { abbreviation } } } } }")

      location = result["data"]["section"]["meetingTimes"].first["location"]
      expect(result["errors"]).to be_nil
      expect(location["display"]).to be_nil
      expect(location["building"]["abbreviation"]).to eq("TBD")
    end

    it "returns null Rate My Professors data for an unrated instructor" do
      result = gql("{ section(crn: 10002) { instructors { name rmp { avgRating } } } }")

      expect(result["data"]["section"]["instructors"].first["rmp"]).to be_nil
    end

    it "returns null for an unknown CRN rather than erroring" do
      result = gql("{ section(crn: 44444) { crn } }")

      expect(result["errors"]).to be_nil
      expect(result["data"]["section"]).to be_nil
    end

    it "returns cancelled sections by CRN" do
      result = gql("{ section(crn: 10999) { status } }")

      expect(result["data"]["section"]["status"]).to eq("cancelled")
    end
  end

  describe "terms, subjects, and instructors" do
    it "returns terms newest first with section counts" do
      result = gql("{ terms { uid name season year sectionCount } }")

      expect(result["data"]["terms"].map { |t| t["uid"] }).to eq([ 202_710, 202_620 ])
      expect(result["data"]["terms"].first["sectionCount"]).to eq(3)
      expect(result["data"]["terms"].first["season"]).to eq("FALL")
    end

    it "returns one term by uid" do
      result = gql("{ term(uid: 202710) { name } }")

      expect(result["data"]["term"]["name"]).to eq("Fall 2026")
    end

    it "returns subjects with counts, narrowed by term" do
      result = gql("{ subjects(termUid: 202710) { subject code sectionCount } }")

      expect(result["data"]["subjects"])
        .to eq([ { "subject" => "Computer Science (COMP)", "code" => "COMP", "sectionCount" => 3 } ])
    end

    it "returns instructors, counted once each" do
      result = gql('{ instructors(q: "byron", first: 10) { totalCount nodes { name pubId } } }')

      expect(result["data"]["instructors"]["totalCount"]).to eq(1)
      expect(result["data"]["instructors"]["nodes"].first["name"]).to eq("Ada Byron")
    end
  end

  describe "errors" do
    it "rejects an invalid enum value at validation time" do
      result = gql('{ sections(filter: { meetsOn: [FUNDAY] }) { totalCount } }')

      expect(result["errors"].first["message"]).to match(/FUNDAY/)
    end

    it "reports a runtime filter error as a GraphQL error" do
      result = gql('{ sections(filter: { beginsAfter: "half past nine" }) { totalCount } }')

      expect(result["errors"].first["message"]).to match(/Invalid time/)
    end

    it "rejects an unknown field" do
      result = gql("{ sections { nodes { gpa } } }")

      expect(result["errors"]).to be_present
      expect(result["data"]).to be_nil
    end

    it "returns 400 for malformed variables JSON" do
      post "/api/graphql", params: { query: "{ terms { uid } }", variables: "{not json" }

      expect(response).to have_http_status(:bad_request)
      expect(json["errors"].first["message"]).to match(/Invalid variables JSON/)
    end

    it "rejects a query that nests deeper than the depth limit" do
      deep = "{ sections { nodes { instructors { rmp { avgRating } } } } }"
      allow(CatalogSchema).to receive(:max_depth).and_return(2)

      expect(gql(deep)["errors"]).to be_present
    end
  end

  describe "schema guarantees" do
    it "exposes no mutations" do
      expect(CatalogSchema.mutation).to be_nil
    end

    it "exposes no instructor contact fields" do
      fields = CatalogSchema.get_type("Instructor").fields.keys

      expect(fields).not_to include("email", "phone", "officeLocation")
    end

    it "caps page size so one query cannot pull the whole catalog" do
      expect(CatalogSchema.default_max_page_size).to eq(Catalog::SectionQuery::MAX_PER_PAGE)
    end
  end
end
