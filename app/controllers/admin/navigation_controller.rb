# frozen_string_literal: true

module Admin
  class NavigationController < Admin::ApplicationController
    def index
      categories = Admin::NavigationRegistry.categories_for(current_user)

      # Transform to JSON-friendly format
      navigation_data = categories.map do |category|
        {
          id: category[:id],
          title: category[:title],
          items: category[:items].map do |item|
            {
              id: item[:id],
              title: item[:title],
              description: item[:description],
              path: resolve_path(item[:path]),
              keywords: item[:keywords] || [],
              read_only: item[:read_only] || false
            }
          end
        }
      end

      render json: {
        categories: navigation_data,
        user: {
          email: current_user.email,
          access_level: current_user.access_level
        }
      }
    end

    private

    def resolve_path(path)
      if path.is_a?(Symbol)
        begin
          helpers.send(path)
        rescue
          nil
        end
      else
        path
      end
    end

  end
end
