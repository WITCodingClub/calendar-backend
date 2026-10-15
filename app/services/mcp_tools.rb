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
      SimilarSections,
      CheckSchedule,
      SearchInstructors,
      GetInstructor,
      SimilarInstructors,
      SearchReviews,
      CatalogGraphql,
      MyCourses,
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

  def self.names = all.map(&:name_value)

  def self.find(name) = all.find { |tool| tool.name_value == name }
end
