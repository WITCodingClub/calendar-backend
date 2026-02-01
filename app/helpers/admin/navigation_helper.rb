# frozen_string_literal: true

module Admin
  module NavigationHelper
    # Check if the new admin UI redesign is enabled
    def admin_ui_redesign_enabled?
      return false unless current_user

      Flipper.enabled?(:admin_ui_redesign, current_user)
    end

    # Get heroicon SVG using the heroicon gem
    def heroicon(name, variant: :outline, **options)
      Heroicon::Engine.render(name, variant: variant, **options)
    rescue
      # Fallback to a simple SVG if icon not found
      content_tag(:svg, class: options[:class], viewBox: "0 0 24 24", fill: "none", stroke: "currentColor") do
        content_tag(:circle, nil, cx: "12", cy: "12", r: "10")
      end
    end

    # Get breadcrumbs for current page
    def admin_breadcrumbs
      return [] unless current_user

      Admin::NavigationRegistry.breadcrumbs_for(request.path, current_user)
    end

    # Check if current path matches navigation item
    def active_nav_item?(path)
      return false unless path

      current_path = request.path
      url_for(path) == current_path
    rescue
      false
    end
  end
end
