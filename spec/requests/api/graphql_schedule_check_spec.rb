# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL scheduleCheck and linked sections", type: :request do
  let(:term) { create(:term) }

  def gql(query, variables: nil)
    post "/api/v1/graphql", params: { query: query, variables: variables }, as: :json
    response.parsed_body
  end

  it "checks a set of sections" do
    lecture = create(:course, term: term, crn: 20452, course_number: 4960, is_section_linked: true, links_fetched_at: Time.current)
    lab     = create(:course, term: term, crn: 20455, course_number: 4960, schedule_type: "LAB", is_section_linked: true, links_fetched_at: Time.current)
    create(:section_link, course: lecture, linked_course: lab)

    body = gql(<<~GRAPHQL, variables: { uid: term.uid, crns: [ 20452 ] })
      query($uid: Int!, $crns: [Int!]!) {
        scheduleCheck(termUid: $uid, crns: $crns) {
          term { uid }
          notFound
          linkProblems { crn problem source partnerOptions }
          totals { creditHours days }
        }
      }
    GRAPHQL

    result = body.dig("data", "scheduleCheck")
    expect(result["term"]).to eq("uid" => term.uid)
    expect(result["linkProblems"]).to eq([ { "crn" => 20452, "problem" => "missing_partner", "source" => "banner", "partnerOptions" => [ [ 20455 ] ] } ])
  end

  it "returns a filter error as a GraphQL error" do
    body = gql("{ scheduleCheck(termUid: 1, crns: [1]) { notFound } }")

    expect(body["errors"].first["message"]).to include("Unknown term_uid")
  end

  it "gives a section's links with their source" do
    lecture = create(:course, term: term, crn: 20452, course_number: 4960, is_section_linked: true, link_identifier: "A2", links_fetched_at: Time.current)
    lab     = create(:course, term: term, crn: 20455, course_number: 4960)
    create(:section_link, course: lecture, linked_course: lab)

    body = gql("query($uid: Int) { section(crn: 20452, termUid: $uid) { linked { required source crns options } } }",
               variables: { uid: term.uid })

    expect(body.dig("data", "section", "linked")).to eq("required" => true, "source" => "banner", "crns" => [ 20455 ], "options" => [ [ 20455 ] ])
  end
end
