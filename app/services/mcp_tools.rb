# frozen_string_literal: true

# The tools of the MCP server (docs/mcp.md). Each tool acts as the signed-in
# user and needs one OAuth scope (McpTools::Scopes). McpTools::Server builds
# the server.
module McpTools
  def self.all
    [
      ListTerms,
      ListSubjects,
      SearchSections,
      GetSection,
      SearchCourses,
      GetCourse,
      ListPrograms,
      GetDegreeRequirements,
      SimilarSections,
      CheckSchedule,
      SearchInstructors,
      GetInstructor,
      SimilarInstructors,
      SearchReviews,
      CatalogGraphql,
      MyCourses,
      MyCourseHistory,
      MyBusyTimes,
      MyFinals,
      ListFriends,
      FriendBusyTimes,
      UniversityEvents,
      MyCalendarSettings,
      PreviewTemplate,
      UpdateClassSettings,
      UpdateCalendarSettings,
      SetNotifications
    ]
  end

  # The MCP App templates (ui:// resources) that tools name in their _meta.
  def self.app_resources = [ WeekGridApp, BusyTimesApp, CatalogApp, FinalsApp ]

  def self.names = all.map(&:name_value)

  def self.find(name) = all.find { |tool| tool.name_value == name }
end
