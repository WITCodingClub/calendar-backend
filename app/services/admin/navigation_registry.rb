# frozen_string_literal: true

module Admin
  class NavigationRegistry
    CATEGORIES = [
      {
        id: :overview, title: "Overview", min_role: :admin,
        items: [
          { id: :dashboard, title: "Dashboard", path: :admin_root_path,
            description: "System overview and statistics", keywords: ["stats", "overview", "home"] }
        ]
      },
      {
        id: :user_management, title: "User Management", min_role: :admin,
        items: [
          { id: :users, title: "Users", path: :admin_users_path,
            description: "Manage user accounts and permissions", keywords: ["accounts", "permissions"] },
          { id: :google_calendars, title: "Google Calendars", path: :admin_calendars_path,
            description: "View user Google Calendars", keywords: ["google", "calendars"] }
        ]
      },
      {
        id: :academic_data, title: "Academic Data", min_role: :admin,
        items: [
          { id: :courses, title: "Courses", path: :admin_courses_path,
            description: "View courses", keywords: ["classes", "schedule"] },
          { id: :faculty, title: "Faculty", path: :admin_faculties_path,
            description: "Manage faculty and RMP ratings", keywords: ["professors", "instructors"] },
          { id: :terms, title: "Terms", path: :admin_terms_path,
            description: "View academic terms", keywords: ["semester", "fall", "spring", "summer"], read_only: true }
        ]
      },
      {
        id: :schedules_calendars, title: "Schedules & Calendars", min_role: :admin,
        items: [
          { id: :finals_schedules, title: "Finals Schedules", path: :admin_finals_schedules_path,
            description: "Manage finals exam schedules", keywords: ["exams", "finals"] },
          { id: :university_events, title: "University Events", path: :admin_university_calendar_events_path,
            description: "Manage university-wide calendar events", keywords: ["holidays", "breaks", "events"] },
          { id: :google_calendar_events, title: "Google Calendar Events", path: :admin_google_calendar_events_path,
            description: "View synced calendar events", keywords: ["events", "sync"], read_only: true }
        ]
      },
      {
        id: :data_sources, title: "Data Sources", min_role: :admin,
        items: [
          { id: :course_catalog, title: "Course Catalog", path: :admin_course_catalog_path,
            description: "Import courses from LeopardWeb", keywords: ["import", "leopardweb", "catalog"], min_role: :super_admin },
          { id: :rmp_ratings, title: "RMP Ratings", path: :admin_rmp_ratings_path,
            description: "View Rate My Professor ratings", keywords: ["rate my professor"], read_only: true }
        ]
      }
    ].freeze

    def self.categories_for(user)
      CATEGORIES.select { |c| user_has_access?(user, c[:min_role] || :admin) }.map do |category|
        { **category, items: items_for(user, category[:items]) }
      end
    end

    def self.items_for_user(user)
      CATEGORIES.flat_map { |c| items_for(user, c[:items]) }.compact
    end

    def self.user_has_access?(user, min_role)
      return false unless user

      levels = { user: 0, admin: 1, super_admin: 2, owner: 3 }
      (levels[user.access_level.to_sym] || 0) >= (levels[min_role.to_sym] || 0)
    end

    def self.items_for(user, items)
      items.select { |item| user_has_access?(user, item[:min_role] || :admin) }
    end
  end
end
