# frozen_string_literal: true

module Admin
  # Centralized admin navigation registry
  # Defines all admin pages with categorization, icons, and role-based visibility
  class NavigationRegistry
    CATEGORIES = [
      {
        id: :overview,
        title: "Overview",
        icon: "home",
        min_role: :admin,
        items: [
          {
            id: :dashboard,
            title: "Dashboard",
            path: :admin_root_path,
            icon: "chart-bar",
            description: "System overview and statistics",
            keywords: ["stats", "overview", "home"]
          }
        ]
      },
      {
        id: :user_management,
        title: "User Management",
        icon: "users",
        min_role: :admin,
        items: [
          {
            id: :users,
            title: "Users",
            path: :admin_users_path,
            icon: "user-group",
            description: "Manage user accounts and permissions",
            keywords: ["accounts", "permissions", "access"]
          },
          {
            id: :google_calendars,
            title: "Google Calendars",
            path: :admin_calendars_path,
            icon: "key",
            description: "View user Google Calendars",
            keywords: ["google", "auth", "calendars"]
          }
        ]
      },
      {
        id: :academic_data,
        title: "Academic Data",
        icon: "academic-cap",
        min_role: :admin,
        items: [
          {
            id: :courses,
            title: "Courses",
            path: :admin_courses_path,
            icon: "book-open",
            description: "View courses",
            keywords: ["classes", "schedule"]
          },
          {
            id: :faculty,
            title: "Faculty",
            path: :admin_faculties_path,
            icon: "user-circle",
            description: "Manage faculty and RMP ratings",
            keywords: ["professors", "instructors", "rate my professor"],
            actions: [
              { title: "Missing RMP IDs", path: :missing_rmp_ids_admin_faculties_path },
              { title: "Directory Status", path: :directory_status_admin_faculties_path }
            ]
          },
          {
            id: :terms,
            title: "Terms",
            path: :admin_terms_path,
            icon: "calendar",
            description: "View academic terms",
            keywords: ["semester", "fall", "spring", "summer"],
            read_only: true
          },
          {
            id: :buildings,
            title: "Buildings",
            path: :admin_buildings_path,
            icon: "office-building",
            description: "View campus buildings",
            keywords: ["locations", "campus"],
            read_only: true
          },
          {
            id: :rooms,
            title: "Rooms",
            path: :admin_rooms_path,
            icon: "location-marker",
            description: "View campus rooms",
            keywords: ["classrooms", "locations"],
            read_only: true
          }
        ]
      },
      {
        id: :schedules_calendars,
        title: "Schedules & Calendars",
        icon: "calendar",
        min_role: :admin,
        items: [
          {
            id: :finals_schedules,
            title: "Finals Schedules",
            path: :admin_finals_schedules_path,
            icon: "clipboard-list",
            description: "Manage finals exam schedules",
            keywords: ["exams", "finals"]
          },
          {
            id: :university_events,
            title: "University Events",
            path: :admin_university_calendar_events_path,
            icon: "calendar-days",
            description: "Manage university-wide calendar events",
            keywords: ["holidays", "breaks", "events"],
            actions: [
              { title: "Sync Events", path: :sync_admin_university_calendar_events_path, method: :post }
            ]
          },
          {
            id: :google_calendar_events,
            title: "Google Calendar Events",
            path: :admin_google_calendar_events_path,
            icon: "calendar-event",
            description: "View synced calendar events",
            keywords: ["events", "sync"],
            read_only: true
          }
        ]
      },
      {
        id: :data_sources,
        title: "Data Sources",
        icon: "database",
        min_role: :admin,
        items: [
          {
            id: :transfer_equivalencies,
            title: "Transfer Equivalencies",
            path: :admin_transfer_equivalencies_path,
            icon: "arrows-right-left",
            description: "View and sync transfer credit equivalencies",
            keywords: ["transfer", "credits", "equivalency", "tes"]
          },
          {
            id: :course_catalog,
            title: "Course Catalog",
            path: :admin_course_catalog_path,
            icon: "document-download",
            description: "Import courses from LeopardWeb",
            keywords: ["import", "leopardweb", "catalog"],
            min_role: :super_admin
          },
          {
            id: :rmp_ratings,
            title: "RMP Ratings",
            path: :admin_rmp_ratings_path,
            icon: "star",
            description: "View Rate My Professor ratings",
            keywords: ["rate my professor", "reviews"],
            read_only: true
          }
        ]
      },
      {
        id: :system_tools,
        title: "System Tools",
        icon: "cog",
        min_role: :super_admin,
        items: [
          {
            id: :background_jobs,
            title: "Background Jobs",
            path: "/admin/jobs",
            icon: "queue-list",
            description: "Monitor and manage job queues",
            keywords: ["jobs", "queue", "mission control", "solid queue"]
          },
          {
            id: :feature_flags,
            title: "Feature Flags",
            path: "/admin/flipper",
            icon: "flag",
            description: "Manage feature toggles",
            keywords: ["flipper", "features", "beta"]
          },
          {
            id: :sql_queries,
            title: "SQL Queries",
            path: "/admin/blazer",
            icon: "code",
            description: "Run SQL queries with Blazer",
            keywords: ["database", "queries", "blazer"]
          },
          {
            id: :performance,
            title: "Performance Monitoring",
            path: "/admin/performance",
            icon: "chart-line",
            description: "View app performance metrics",
            keywords: ["monitoring", "speed", "requests"]
          },
          {
            id: :database_insights,
            title: "Database Insights",
            path: "/admin/pghero",
            icon: "server",
            description: "PostgreSQL monitoring with PgHero",
            keywords: ["postgres", "pghero", "db"]
          },
          {
            id: :logs,
            title: "Logs",
            path: "/admin/logs",
            icon: "document-text",
            description: "View application logs",
            keywords: ["errors", "logging", "logster"]
          },
          {
            id: :console_audits,
            title: "Console Audits",
            path: "/admin/audits",
            icon: "shield-check",
            description: "Audit console sessions",
            keywords: ["security", "audit", "console", "audits1984"]
          }
        ]
      },
      {
        id: :owner_only,
        title: "Owner Only",
        icon: "lock-closed",
        min_role: :owner,
        items: [
          {
            id: :service_account,
            title: "Service Account",
            path: :admin_service_account_index_path,
            icon: "identification",
            description: "Manage Google service account OAuth",
            keywords: ["oauth", "service account", "google"]
          }
        ]
      }
    ].freeze

    # Get all categories visible to the given user
    def self.categories_for(user)
      CATEGORIES.select do |category|
        user_has_access?(user, category[:min_role] || :admin)
      end.map do |category|
        {
          **category,
          items: items_for(user, category[:items])
        }
      end
    end

    # Get all navigation items (flat list) visible to the given user
    def self.items_for_user(user)
      CATEGORIES.flat_map do |category|
        items_for(user, category[:items])
      end.compact
    end

    # Get all navigation items for search/command palette
    def self.searchable_items_for(user)
      items_for_user(user).map do |item|
        {
          id: item[:id],
          title: item[:title],
          description: item[:description],
          path: item[:path],
          icon: item[:icon],
          keywords: item[:keywords] || [],
          read_only: item[:read_only] || false
        }
      end
    end

    # Check if user has minimum required access level
    def self.user_has_access?(user, min_role)
      return false unless user

      access_levels = {
        user: 0,
        admin: 1,
        super_admin: 2,
        owner: 3
      }

      user_level = access_levels[user.access_level.to_sym]
      required_level = access_levels[min_role.to_sym]

      user_level >= required_level
    end

    # Filter items based on user access
    def self.items_for(user, items)
      items.select do |item|
        min_role = item[:min_role] || :admin
        user_has_access?(user, min_role)
      end
    end

    # Get breadcrumbs for a given path
    def self.breadcrumbs_for(path, user)
      item = find_item_by_path(path)
      return [] unless item

      category = find_category_for_item(item[:id])
      return [] unless category

      [
        { title: "Admin", path: :admin_root_path },
        { title: category[:title], path: nil },
        { title: item[:title], path: nil }
      ]
    end

    private_class_method def self.find_item_by_path(path)
      CATEGORIES.each do |category|
        category[:items].each do |item|
          return item if item[:path].to_s == path.to_s
        end
      end
      nil
    end

    private_class_method def self.find_category_for_item(item_id)
      CATEGORIES.find do |category|
        category[:items].any? { |item| item[:id] == item_id }
      end
    end

  end
end
