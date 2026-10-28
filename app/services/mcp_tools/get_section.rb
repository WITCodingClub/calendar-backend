# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/sections/:crn. GraphQL: section.
  class GetSection < BaseTool
    BANNER_URL = "#{Catalog::LeopardWebClient::BASE_URL}%s?term=<term_uid>&courseReferenceNumber=<crn>".freeze

    # Banner's own pages need no sign-in. Catalog::BannerThrottle says why the
    # model reads only a few.
    BANNER_HINT = "For a current or future term, when the advisory says the section data is more than 2 days old " \
                  "or has no refresh time, " \
                  "and you can fetch web pages, read Banner itself. " \
                  "Send one GET for each CRN, one at a time, for at most 10 CRNs, because Banner fails after " \
                  "about 40 requests in a minute. The term_uid is the Banner term code. " \
                  "#{format(BANNER_URL, 'getEnrollmentInfo')} gives the seats and the waitlist as HTML. " \
                  "#{format(BANNER_URL, 'getFacultyMeetingTimes')} gives the meeting times, rooms, and instructors " \
                  "as JSON. Tell the student which data came from Banner."

    tool_name "get_section"
    title "Get a course section"
    description "Gets one course section by CRN: meeting times, rooms, instructors, seats, the waitlist, and the final exam. " \
                "It also finds cancelled sections. Not every section has a waitlist: a waitlist capacity of 0 " \
                "means none, and null means WIT Calendar does not know yet. For a full section with a waitlist, the student joins it before they ask for a " \
                "capacity override. When the data is more than #{Courses::Processor::CATALOG_FRESH_FOR.in_hours.to_i} " \
                "hours old in a current or future term, this tool asks WIT Calendar to read Banner again in the " \
                "background. The answer does not wait for it. #{BANNER_HINT}"
    requires_scope "catalog"
    meta CatalogApp.tool_meta
    academic_planning :sections
    input_schema(
      properties: {
        crn:      { type: "integer", description: "The section CRN, for example 12345." },
        term_uid: TERM_SCHEMA
      },
      required: [ "crn" ]
    )
    output_schema(Schemas::SECTION)

    def perform(crn:, term_uid: nil)
      section = find_section(crn, term_uid)
      refresh_stale_sections(section.term.uid, [ section.crn ])
      Catalog::SectionSerializer.new(section).as_json
    end
  end
end
