# frozen_string_literal: true

class RateMyProfessorService < ApplicationService
  require "faraday"
  require "json"

  BASE_URL = "https://www.ratemyprofessors.com/graphql"
  WENTWORTH_SCHOOL_ID = "U2Nob29sLTExNTg="

  SEARCH_QUERY = <<~GRAPHQL
    query NewSearchTeachersQuery(
      $query: TeacherSearchQuery!
      $count: Int
    ) {
      newSearch {
        teachers(query: $query, first: $count) {
          didFallback
          edges {
            cursor
            node {
              id
              legacyId
              firstName
              lastName
              department
              departmentId
              school {
                legacyId
                name
                id
              }
              avgRating
              avgDifficulty
              numRatings
              wouldTakeAgainPercentRounded
              mandatoryAttendance {
                yes
                no
                neither
                total
              }
              takenForCredit {
                yes
                no
                neither
                total
              }
              ratingsDistribution {
                total
                r1
                r2
                r3
                r4
                r5
              }
              lockStatus
            }
          }
        }
      }
    }
  GRAPHQL

  RATINGS_QUERY = <<~GRAPHQL
    query RatingsListQuery(
      $id: ID!
      $count: Int
      $cursor: String
    ) {
      node(id: $id) {
        __typename
        ... on Teacher {
          ratings(first: $count, after: $cursor) {
            edges {
              cursor
              node {
                id
                legacyId
                comment
                date
                class
                helpfulRating
                clarityRating
                difficultyRating
                wouldTakeAgain
                grade
                thumbsUpTotal
                thumbsDownTotal
                isForOnlineClass
                isForCredit
                attendanceMandatory
                ratingTags
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      }
    }
  GRAPHQL

  TEACHER_DETAILS_QUERY = <<~GRAPHQL
    query TeacherRatingsPageQuery(
      $id: ID!
    ) {
      node(id: $id) {
        __typename
        ... on Teacher {
          id
          legacyId
          firstName
          lastName
          department
          departmentId
          avgRating
          avgDifficulty
          numRatings
          wouldTakeAgainPercent
          isProfCurrentUser
          isSaved
          lockStatus
          school {
            legacyId
            name
            city
            state
            country
            avgRating
            numRatings
            id
          }
          courseCodes {
            courseName
            courseCount
          }
          ratingsDistribution {
            r1
            r2
            r3
            r4
            r5
            total
          }
          teacherRatingTags {
            id
            legacyId
            tagName
            tagCount
          }
          relatedTeachers {
            legacyId
            firstName
            lastName
            avgRating
            id
          }
          ratings(first: 20) {
            edges {
              cursor
              node {
                id
                legacyId
                comment
                date
                class
                helpfulRating
                clarityRating
                difficultyRating
                wouldTakeAgain
                grade
                thumbsUpTotal
                thumbsDownTotal
                isForOnlineClass
                isForCredit
                attendanceMandatory
                textbookUse
                ratingTags
                flagStatus
                adminReviewedAt
                createdByUser
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
        id
      }
    }
  GRAPHQL

  def search_professors(name, school_id: WENTWORTH_SCHOOL_ID, count: 10)
    # Cache professor searches for 24 hours since professor lists change infrequently
    cache_key = "rmp:search:#{school_id}:#{name.parameterize}:#{count}"

    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      response = make_request(
        query: SEARCH_QUERY,
        operation_name: "NewSearchTeachersQuery",
        variables: {
          query: {
            text: name,
            schoolID: school_id
          },
          count: count
        }
      )

      response.body
    end
  end

  def get_teacher_details(teacher_id)
    # Cache teacher details for 12 hours since basic info changes infrequently
    cache_key = "rmp:teacher:#{teacher_id}"

    Rails.cache.fetch(cache_key, expires_in: 12.hours) do
      response = make_request(
        query: TEACHER_DETAILS_QUERY,
        operation_name: "TeacherRatingsPageQuery",
        variables: { id: teacher_id }
      )

      response.body
    end
  end

  def get_ratings(teacher_id, count: 100, cursor: nil)
    # Cache individual rating pages for 6 hours
    # Note: get_all_ratings() will use this cached data
    cache_key = "rmp:ratings:#{teacher_id}:#{count}:#{cursor || 'start'}"

    Rails.cache.fetch(cache_key, expires_in: 6.hours) do
      response = make_request(
        query: RATINGS_QUERY,
        operation_name: "RatingsListQuery",
        variables: {
          id: teacher_id,
          count: count,
          cursor: cursor
        }
      )

      response.body
    end
  end

  def get_all_ratings(teacher_id)
    all_ratings = []
    cursor = nil
    has_next_page = true

    while has_next_page
      response = get_ratings(teacher_id, cursor: cursor)
      ratings_data = response.dig("data", "node", "ratings")

      break unless ratings_data

      edges = ratings_data["edges"] || []
      all_ratings.concat(edges.pluck("node"))

      page_info = ratings_data["pageInfo"]
      has_next_page = page_info["hasNextPage"]
      cursor = page_info["endCursor"]
    end

    all_ratings
  end

  # Generate URL to add a professor to RMP
  # Note: RMP requires reCAPTCHA, so automated submission via GraphQL is not possible
  def add_professor_url(first_name: nil, last_name: nil, school_id: WENTWORTH_SCHOOL_ID)
    "https://www.ratemyprofessors.com/add/professor"
  end

  # Generate WIT faculty directory URL for a professor
  def faculty_directory_url(first_name:, last_name:)
    "https://wit.edu/faculty-staff-directory?search=#{URI.encode_www_form_component(first_name)}+#{URI.encode_www_form_component(last_name)}&dept=&school=&employee_type=All"
  end

  private

  def make_request(query:, operation_name:, variables:)
    connection = Faraday.new(url: BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
    end

    connection.post do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["Accept"] = "*/*"
      req.headers["Authorization"] = "null"
      req.headers["Origin"] = "https://www.ratemyprofessors.com"
      req.headers["Referer"] = "https://www.ratemyprofessors.com/"

      req.body = {
        query: query,
        operationName: operation_name,
        variables: variables
      }
    end
  end

end
