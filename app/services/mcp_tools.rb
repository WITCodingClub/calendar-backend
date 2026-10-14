# frozen_string_literal: true

# The tools of the MCP server (docs/mcp.md). Every tool is read-only and
# acts as the signed-in user. McpTools::Server builds the server.
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
      UniversityEvents
    ]
  end

  def self.names = all.map(&:name_value)
end
