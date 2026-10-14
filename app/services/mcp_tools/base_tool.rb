# frozen_string_literal: true

module McpTools
  # Base for every MCP tool. Every tool is read-only.
  #
  # A subclass sets its name, description, and input schema, and defines
  # perform(user:, **arguments). perform returns a Hash: the tool sends it as
  # structured content and as JSON text. A bad argument raises
  # McpTools::ToolError, which goes back to the client as a tool error with
  # the message. Any other error goes to the MCP server's exception reporter
  # (McpTools::Server).
  class BaseTool < MCP::Tool
    READ_ONLY = {
      read_only_hint:   true,
      destructive_hint: false,
      idempotent_hint:  true,
      open_world_hint:  false
    }.freeze

    # A date in a tool argument: YYYY-MM-DD.
    DATE_SCHEMA = { type: "string", format: "date", description: "A date in YYYY-MM-DD format." }.freeze
    PAGE_SCHEMA = { type: "integer", minimum: 1, description: "The page, from 1." }.freeze
    TERM_SCHEMA = {
      type:        "integer",
      description: "The term uid from list_terms, for example 202610. Leave it out for the current term."
    }.freeze

    class << self
      def inherited(subclass)
        super
        subclass.annotations(READ_ONLY)
      end

      def call(server_context:, **arguments)
        data = new(server_context[:user], request: server_context[:request]).perform(**arguments)

        MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
      rescue ToolError, ActiveRecord::RecordNotFound => e
        # The message is for the person who asked: a term that does not exist,
        # a friend who does not share. These are answers, not faults, so they
        # are not reported, the same as a 404 from the API.
        error_response(e.message)
      rescue Pundit::NotAuthorizedError
        # Pundit's message names the policy method, which means nothing to the
        # person who asked.
        error_response("You do not have access to that.")
      end

      private

      def error_response(message)
        MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
      end
    end

    attr_reader :user, :request

    def initialize(user, request: nil)
      @user    = user
      @request = request
    end

    private

    # Call before a search that ranks q by meaning. A search with no words
    # embeds nothing, so it is free.
    def spend_semantic_search!(q, semantic)
      SemanticBudget.new(request).spend! if semantic && q.present?
    end

    # page and per_page, the same as the REST API.
    def page_params(page, per_page, default:, max:)
      [ [ page.to_i, 1 ].max, (per_page || default).to_i.clamp(1, max) ]
    end

    def page_meta(page, per_page, total)
      { page: page, per_page: per_page, total_count: total, total_pages: (total.to_f / per_page).ceil }
    end

    def authorize(record, query)
      Pundit.authorize(user, record, query)
    end

    def find_term(uid)
      return Term.current || raise(ToolError, "There is no current term. Pass a term_uid from list_terms.") if uid.nil?

      Term.find_by(uid: uid) || raise(ToolError, "No term with uid #{uid}. Call list_terms for the uids.")
    end

    # A section by CRN, cancelled or not, the same lookup as
    # GET /api/v1/catalog/sections/:crn.
    def find_section(crn, term_uid)
      term     = find_term(term_uid)
      relation = Catalog::SectionQuery.new.call(crns: [ crn ], term_uid: term.uid, include_cancelled: true)

      Catalog::SectionQuery.with_associations(relation).first ||
        raise(ToolError, "No section with CRN #{crn} in term #{term.uid}")
    end

    def find_instructor(pub_id)
      Faculty.includes(:rating_distribution).find_by_public_id(pub_id.to_s.strip) ||
        raise(ToolError, "No instructor #{pub_id}. Call search_instructors for the ids.")
    end

    def parse_date(value, name)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ToolError, "#{name} must be a date in YYYY-MM-DD format"
    end

    def date_range(start_date, end_date)
      from = parse_date(start_date, "start_date")
      to   = parse_date(end_date, "end_date")
      raise ToolError, "end_date must not be before start_date" if to < from

      days = (to - from).to_i + 1
      raise ToolError, "the range must be #{BusyBlocks::MAX_DAYS} days or fewer" if days > BusyBlocks::MAX_DAYS

      [ from, to ]
    end

    def limit_value(value, default:, max:)
      (value || default).to_i.clamp(1, max)
    end
  end
end
