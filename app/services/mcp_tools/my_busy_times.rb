# frozen_string_literal: true

module McpTools
  class MyBusyTimes < BaseTool
    tool_name "my_busy_times"
    title "My busy times"
    description "Lists the times I am busy between two dates: classes, final exams, and saved friend meetings. " \
                "Use it for \"am I free on Thursday afternoon\" and \"when do I have class this week\". " \
                "Days with no classes (holidays, study days) are left out. At most #{BusyBlocks::MAX_DAYS} days."
    requires_scope "schedule:read"
    input_schema(
      properties: { start_date: DATE_SCHEMA, end_date: DATE_SCHEMA },
      required:   %w[start_date end_date]
    )
    output_schema(Schemas.object(Schemas::BUSY_TIMES_PROPERTIES))

    def perform(start_date:, end_date:)
      authorize user, :show?
      from, to = date_range(start_date, end_date)

      BusyBlocksSerializer.new(BusyBlocks.new(user, from: from, to: to).call, from: from, to: to).as_json
    end
  end
end
