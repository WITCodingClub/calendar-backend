# frozen_string_literal: true

module McpTools
  # Base for every MCP tool. A tool that changes data inherits
  # McpTools::BaseWriteTool instead.
  #
  # A subclass sets its name, description, input schema, and the scope it
  # needs (requires_scope, from McpTools::Scopes), and defines
  # perform(**arguments). perform returns a Hash: the tool sends it as
  # structured content and as JSON text. A bad argument raises
  # McpTools::ToolError, which goes back to the client as a tool error with
  # the message. Any other error goes to the MCP server's exception reporter
  # (McpTools::Server).
  #
  # A tool whose answer a student can use to plan courses calls
  # academic_planning. Its result then carries an advisory: ADVISORY, which
  # tells the student to confirm the plan with their program director and
  # advisor, and the refresh times of the sources the tool names
  # (Catalog::Freshness).
  #
  # Each tool sets output_schema: the JSON Schema of the Hash that perform
  # returns. The shared parts are in McpTools::Schemas. academic_planning adds
  # ADVISORY_SCHEMA to it, so a tool's own schema leaves the advisory out.
  #
  # A tool can call links with a block that takes the result and returns
  # page_link Hashes (McpTools::PageLinks). Each one goes in the content after
  # the JSON text, as a resource_link to a WIT Calendar page. The structured
  # content does not change.
  class BaseTool < MCP::Tool
    include PageLinks
    READ_ONLY = {
      read_only_hint:   true,
      destructive_hint: false,
      idempotent_hint:  true,
      open_world_hint:  false
    }.freeze

    DATE_SCHEMA = { type: "string", format: "date", description: "A date in YYYY-MM-DD format." }.freeze
    ADVISORY = "WIT Calendar is not an official Wentworth service. It copies this data from official Wentworth " \
               "sources on a schedule, so the data can be out of date. data_sources gives each source, how often " \
               "WIT Calendar refreshes it, and when it last did. Tell the student to confirm any course plan with " \
               "their #{Policy::PLAN_CONFIRMERS} before they register, drop a course, or change their plan."

    # The advisory key in the result of an academic planning tool. A term
    # source (Catalog::Freshness::TERM_SOURCES) has terms, the other sources
    # have last_refreshed_at. key names the source (Catalog::Freshness::SOURCES).
    ADVISORY_SCHEMA = Schemas.object(
      message:      Schemas::STRING,
      data_sources: Schemas.array(
        Schemas.object(
          {
            key:               { type: "string", enum: Catalog::Freshness::SOURCES.keys.map(&:to_s) },
            data:              Schemas::STRING,
            source:            Schemas::STRING,
            schedule:          Schemas::STRING,
            last_refreshed_at: Schemas.nullable(Schemas::DATE_TIME),
            terms:             Schemas.array(
              Schemas.object(term_uid: Schemas::INTEGER, term: Schemas::STRING, last_refreshed_at: Schemas.nullable(Schemas::DATE_TIME))
            )
          },
          optional: %i[last_refreshed_at terms]
        )
      )
    ).freeze

    # Errors whose message answers the person who asked: a term that does not
    # exist, a filter value that is not valid, a student with no program.
    # They go back as a tool error with the message and are not reported, the
    # same as a 4xx answer from the API.
    ANSWER_ERRORS = [
      ToolError,
      ActiveRecord::RecordNotFound,
      Catalog::FilterError,
      AcademicProfiles::Error
    ].freeze

    FLAG_OFF_MESSAGE = "This feature is not enabled for this student yet. Do not call the tool again."

    PAGE_SCHEMA = { type: "integer", minimum: 1, description: "The page, from 1." }.freeze
    SIMILAR_LIMIT_SCHEMA = { type: "integer", minimum: 1, maximum: Embeddable::MAX_SIMILAR_LIMIT }.freeze
    TERM_SCHEMA = {
      type:        "integer",
      description: "The term uid from list_terms, for example 202610. Leave it out for the current term."
    }.freeze

    # The per_page argument of a catalog list (Catalog::Page::MCP_SIZES).
    def self.per_page_schema(list)
      {
        type: "integer", minimum: 1, maximum: Catalog::Page.max_size(list, surface: :mcp),
        description: "Default #{Catalog::Page.default_size(list, surface: :mcp)}."
      }
    end

    class << self
      def inherited(subclass)
        super
        subclass.annotations(READ_ONLY)
      end

      attr_reader :required_scope, :required_flag, :links_block

      # The annotations carry the tool's title as well. Directories, such as
      # the Claude connector directory, read annotations.title, not the
      # top-level title.
      def annotations_value
        value = super
        return value if value.nil? || value.title || title_value.nil?

        MCP::Tool::Annotations.new(
          read_only_hint:   value.read_only_hint,
          destructive_hint: value.destructive_hint,
          idempotent_hint:  value.idempotent_hint,
          open_world_hint:  value.open_world_hint,
          title:            title_value
        )
      end

      # The pages of a result: links { |result| [ page_link(...) ] }. The
      # block runs on the tool instance, so it can read user.
      def links(&block)
        @links_block = block
      end

      # The result of this tool carries ADVISORY and the refresh times of
      # its sources (keys of Catalog::Freshness::SOURCES).
      def academic_planning(*sources)
        unknown = sources - Catalog::Freshness::SOURCES.keys
        raise ArgumentError, "unknown data source #{unknown.join(', ')}" if unknown.any?

        @data_sources = sources
        apply_output_schema
      end

      attr_reader :data_sources

      def academic_planning? = !@data_sources.nil?

      # The JSON Schema of the result (the MCP outputSchema). The schema of an
      # academic planning tool also gets the advisory, whichever of the two
      # calls comes first.
      def output_schema(value = nil)
        return super() if value.nil?

        @own_output_schema = value
        apply_output_schema
      end

      def requires_scope(name)
        raise ArgumentError, "unknown MCP scope #{name}" unless Scopes::BY_NAME.key?(name)

        @required_scope = name
        description("#{description} Needs the \"#{Scopes.label(name)}\" permission.") unless Scopes::BY_NAME[name].default
      end

      # The Flipper flag (FeatureFlags) that must be on for the user to call
      # this tool. Use the flag of the matching API endpoint. tools/list
      # still lists the tool to every token (McpTools::Server, CACHE_SCOPE),
      # so only the call checks the flag.
      def requires_flag(name)
        raise ArgumentError, "unknown feature flag #{name}" unless FeatureFlags::MAP.value?(name)

        @required_flag = name
      end

      def call(server_context:, **arguments)
        unless Array(server_context[:scopes]).include?(required_scope)
          Yabeda.calendar.mcp_scope_denials_total.increment({ scope: required_scope.to_s, mode: "tool_error" })
          links = PageLinks.supported?(server_context) ? [ PageLinks.connected_apps_link ] : []
          return error_response(missing_scope_message, links: links)
        end
        return error_response(FLAG_OFF_MESSAGE) if required_flag && !Flipper.enabled?(required_flag, server_context[:user])

        unknown = arguments.keys.map(&:to_s) - argument_names
        raise ToolError, unknown_arguments_message(unknown) if unknown.any?

        tool = new(server_context[:user], request: server_context[:request], server_context: server_context)
        data = tool.perform(**arguments)
        # A write tool asks the student to confirm first (McpTools::Confirmation).
        return data if data.is_a?(MCP::Server::InputRequiredResult)

        data = data.merge(advisory: advisory) if academic_planning?
        links = PageLinks.supported?(server_context) ? tool.page_links(data) : []

        MCP::Tool::Response.new([ { type: "text", text: data.to_json }, *links ], structured_content: data)
      rescue *ANSWER_ERRORS => e
        error_response(e.message)
      rescue Pundit::NotAuthorizedError
        # Pundit's message names the policy method, which means nothing to the
        # person who asked.
        error_response("You do not have access to that.")
      end

      private

      # The SDK checks the arguments against the input schema, but the schema
      # allows other keys. perform would then raise ArgumentError, and the
      # client would get an internal error with no message.
      def argument_names
        input_schema_value.to_h.fetch(:properties, {}).keys.map(&:to_s)
      end

      def unknown_arguments_message(unknown)
        accepted = argument_names.empty? ? "no arguments" : "only #{argument_names.join(', ')}"
        "Unknown argument #{unknown.join(', ')}. #{tool_name} takes #{accepted}."
      end

      def apply_output_schema
        return if @own_output_schema.nil?

        schema = @own_output_schema
        if academic_planning?
          schema = schema.merge(
            properties: schema.fetch(:properties, {}).merge(advisory: ADVISORY_SCHEMA),
            required:   [ *schema[:required], "advisory" ]
          )
        end
        @output_schema_value = MCP::Tool::OutputSchema.new(schema)
      end

      def advisory
        { message: ADVISORY, data_sources: Catalog::Freshness.call(data_sources) }
      end

      def missing_scope_message
        label = Scopes.label(required_scope)
        "This needs the \"#{label}\" permission, which this app does not have. To add it, disconnect " \
          "WIT Calendar in this app's connector settings, connect again, and check \"#{label}\". " \
          "Settings in WIT Calendar shows the permissions that this app has."
      end

      def error_response(message, links: [])
        MCP::Tool::Response.new([ { type: "text", text: message }, *links ], error: true)
      end
    end

    attr_reader :user, :request, :server_context

    # server_context: the MCP::ServerContext of the call, or a Hash in specs.
    def initialize(user, request: nil, server_context: nil)
      @user           = user
      @request        = request
      @server_context = server_context
    end

    # The resource_link content items of a result, from the links block. A
    # link is extra, so a fault in a links block is reported and the result
    # goes out without links.
    def page_links(data)
      block = self.class.links_block
      block ? Array(instance_exec(data, &block)).compact : []
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { user_id: user&.id })
      []
    end

    private

    # Counts a semantic search against the catalog/semantic budget, the same
    # budget as REST and GraphQL. The request carries the user's token, so
    # Rack::Attack counts it against that user, not the shared address of the
    # client. Without a request (a tool called outside one) nothing counts.
    def spend_semantic_search!(q, semantic)
      return if request.nil? || !Catalog::SemanticSearch.requested?(semantic, q)
      return unless Rack::Attack.semantic_search_throttled?(request.env)

      raise ToolError, "Too many semantic searches. Wait a minute, or search without semantic."
    end

    def authorize(record, query)
      Pundit.authorize(user, record, query)
    end

    # The term with this uid. Without one, the current term.
    def find_term(uid)
      return Term.find_by_uid!(uid) unless uid.nil?

      Term.current || raise(ToolError, "There is no current term. Pass a term_uid from list_terms.")
    end

    # A refresh is extra, so a fault is reported, not raised.
    def refresh_stale_sections(term_uid, crns)
      Catalog::StaleSections.refresh(term_uid, crns)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { user_id: user&.id })
    end

    # A meeting time of a course the user takes, by the id from my_courses.
    def find_my_meeting_time(id)
      Course::MeetingTime.joins(course: :enrollments)
                         .where(enrollments: { user_id: user.id })
                         .includes(course: [ :faculties, :term ], rooms: :building)
                         .find_by_public_id(id.to_s) ||
        raise(ToolError, "No class meeting #{id} in your courses. Call my_courses for the ids.")
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
