# frozen_string_literal: true

# Middleware to inject command palette into all HTML pages, including mounted engines
class CommandPaletteInjector
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Use REQUEST_PATH to get the full original path including mount points
    path = env["REQUEST_PATH"] || env["PATH_INFO"]
    puts "=== CommandPaletteInjector: Processing #{path} ==="
    puts "Content-Type: #{headers['Content-Type']}"
    puts "Is admin route: #{admin_route?(path)}"

    # Only inject for HTML responses
    unless html_response?(headers)
      puts "SKIPPING: Not HTML response"
      return [status, headers, response]
    end

    # Only inject for admin routes
    unless admin_route?(path)
      puts "SKIPPING: Not admin route"
      return [status, headers, response]
    end

    # Admin routes are already protected by AdminConstraint, so if we got here, user is admin
    puts "✅ INJECTING SCRIPT!"

    # Inject the script
    new_response = inject_script(response)

    puts "Script injected. Response size: #{new_response.bytesize}"

    # Update content length
    headers.delete("Content-Length") # Remove old content length, let Rack recalculate

    [status, headers, [new_response]]
  end

  private

  def html_response?(headers)
    content_type = headers["Content-Type"]
    content_type&.include?("text/html")
  end

  def admin_route?(path)
    path.start_with?("/admin") && !api_route?(path)
  end

  def api_route?(path)
    path.start_with?("/admin/navigation") || path.start_with?("/api")
  end

  def inject_script(response)
    body = response_body(response)

    # Build the injection script
    script = build_injection_script

    # Inject before closing body tag, or at the end if no body tag
    if body.include?("</body>")
      body.sub("</body>", "#{script}</body>")
    else
      body + script
    end
  end

  def response_body(response)
    body = ""
    response.each { |part| body << part }
    response.close if response.respond_to?(:close)
    body
  end

  def build_injection_script
    <<~HTML
      <script>
        (function() {
          // Only inject if command palette doesn't already exist
          if (document.querySelector('[data-palette-injected="true"]')) {
            return;
          }

          let paletteContainer = null;
          let navigationData = null;
          let selectedIndex = 0;
          let filteredItems = [];

          // Keyboard listener for Cmd+K
          document.addEventListener('keydown', async function(e) {
            if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
              e.preventDefault();
              await openPalette();
            }
          });

          async function openPalette() {
            if (!paletteContainer) {
              await buildPalette();
            }
            paletteContainer.classList.remove('hidden');
            const input = paletteContainer.querySelector('input');
            if (input) {
              input.value = '';
              input.focus();
              showAllItems();
            }
          }

          function closePalette() {
            if (paletteContainer) {
              paletteContainer.classList.add('hidden');
            }
          }

          async function buildPalette() {
            // Fetch navigation data
            try {
              const response = await fetch('/admin/navigation');
              if (!response.ok) return;
              const data = await response.json();
              navigationData = data;
            } catch (error) {
              console.error('Failed to fetch navigation:', error);
              return;
            }

            // Create container
            paletteContainer = document.createElement('div');
            paletteContainer.setAttribute('data-palette-injected', 'true');
            paletteContainer.className = 'fixed inset-0 bg-black/60 backdrop-blur-sm flex items-start justify-center pt-[15vh] z-50 hidden';
            paletteContainer.style.zIndex = '99999';

            // Click backdrop to close
            paletteContainer.addEventListener('click', function(e) {
              if (e.target === paletteContainer) {
                closePalette();
              }
            });

            // Inner modal
            const modal = document.createElement('div');
            modal.className = 'bg-white rounded-xl shadow-2xl w-full max-w-2xl mx-4 overflow-hidden border border-gray-200';
            modal.addEventListener('click', function(e) {
              e.stopPropagation();
            });

            // Search input
            const searchContainer = createSearchInput();
            modal.appendChild(searchContainer);

            // Results container
            const resultsContainer = document.createElement('div');
            resultsContainer.id = 'palette-results';
            resultsContainer.className = 'max-h-96 overflow-y-auto';
            modal.appendChild(resultsContainer);

            // Footer
            const footer = createFooter();
            modal.appendChild(footer);

            paletteContainer.appendChild(modal);
            document.body.appendChild(paletteContainer);

            // Populate items
            showAllItems();
          }

          function createSearchInput() {
            const container = document.createElement('div');
            container.className = 'relative';

            const iconDiv = document.createElement('div');
            iconDiv.className = 'absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none';
            const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            icon.setAttribute('class', 'w-5 h-5 text-gray-400');
            icon.setAttribute('fill', 'none');
            icon.setAttribute('stroke', 'currentColor');
            icon.setAttribute('viewBox', '0 0 24 24');
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('stroke-linecap', 'round');
            path.setAttribute('stroke-linejoin', 'round');
            path.setAttribute('stroke-width', '2');
            path.setAttribute('d', 'M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z');
            icon.appendChild(path);
            iconDiv.appendChild(icon);

            const input = document.createElement('input');
            input.type = 'text';
            input.placeholder = 'Search or jump to...';
            input.className = 'w-full pl-12 pr-4 py-4 text-base border-0 border-b border-gray-200 focus:outline-none focus:ring-0';

            input.addEventListener('input', handleSearch);
            input.addEventListener('keydown', handleKeyboard);

            container.appendChild(iconDiv);
            container.appendChild(input);
            return container;
          }

          function createFooter() {
            const footer = document.createElement('div');
            footer.className = 'px-4 py-3 bg-gray-50 border-t border-gray-200 flex items-center justify-between text-xs text-gray-500';

            const leftHints = document.createElement('div');
            leftHints.className = 'flex items-center gap-3';

            const navHint = createKeyHint('↑↓', 'Navigate');
            const selectHint = createKeyHint('↵', 'Select');
            leftHints.appendChild(navHint);
            leftHints.appendChild(selectHint);

            const closeHint = createKeyHint('ESC', 'Close');

            footer.appendChild(leftHints);
            footer.appendChild(closeHint);
            return footer;
          }

          function createKeyHint(key, label) {
            const hint = document.createElement('div');
            hint.className = 'flex items-center gap-1';

            const kbd = document.createElement('kbd');
            kbd.className = 'px-2 py-1 bg-white border border-gray-300 rounded text-xs font-medium shadow-sm';
            kbd.textContent = key;

            const span = document.createElement('span');
            span.textContent = label;

            hint.appendChild(kbd);
            hint.appendChild(span);
            return hint;
          }

          function handleSearch(e) {
            const query = e.target.value.toLowerCase().trim();
            if (!query) {
              showAllItems();
              return;
            }

            // Filter items
            filteredItems = [];
            navigationData.categories.forEach(function(category) {
              category.items.forEach(function(item) {
                if (!item.path) return;
                const searchText = (item.title + ' ' + (item.description || '') + ' ' + category.title).toLowerCase();
                if (searchText.includes(query)) {
                  filteredItems.push({ item: item, category: category });
                }
              });
            });

            selectedIndex = 0;
            renderItems(filteredItems);
          }

          function showAllItems() {
            filteredItems = [];
            navigationData.categories.forEach(function(category) {
              category.items.forEach(function(item) {
                if (item.path) {
                  filteredItems.push({ item: item, category: category });
                }
              });
            });
            selectedIndex = 0;
            renderItems(filteredItems);
          }

          function renderItems(items) {
            const container = document.getElementById('palette-results');
            while (container.firstChild) {
              container.removeChild(container.firstChild);
            }

            if (items.length === 0) {
              const noResults = document.createElement('div');
              noResults.className = 'px-4 py-8 text-center text-sm text-gray-500';
              noResults.textContent = 'No results found';
              container.appendChild(noResults);
              return;
            }

            items.forEach(function(data, index) {
              const itemDiv = createItemElement(data.item, data.category, index);
              container.appendChild(itemDiv);
            });
          }

          function createItemElement(item, category, index) {
            const itemDiv = document.createElement('div');
            itemDiv.className = 'px-4 py-2.5 cursor-pointer transition border-l-2';
            itemDiv.className += (index === selectedIndex) ? ' bg-red-50 border-l-red-700' : ' hover:bg-gray-50 border-l-transparent';

            itemDiv.addEventListener('click', function() {
              window.location.href = item.path;
            });

            const wrapper = document.createElement('div');
            wrapper.className = 'flex items-center justify-between gap-3';

            const left = document.createElement('div');
            left.className = 'flex-1 min-w-0';

            const title = document.createElement('div');
            title.className = 'font-medium text-sm text-gray-900 truncate';
            title.textContent = item.title;
            left.appendChild(title);

            if (item.description) {
              const desc = document.createElement('div');
              desc.className = 'text-xs text-gray-500 truncate mt-0.5';
              desc.textContent = item.description;
              left.appendChild(desc);
            }

            const right = document.createElement('span');
            right.className = 'text-xs text-gray-400 uppercase';
            right.textContent = category.title;

            wrapper.appendChild(left);
            wrapper.appendChild(right);
            itemDiv.appendChild(wrapper);

            return itemDiv;
          }

          function handleKeyboard(e) {
            if (e.key === 'Escape') {
              e.preventDefault();
              closePalette();
            } else if (e.key === 'ArrowDown') {
              e.preventDefault();
              selectedIndex = Math.min(selectedIndex + 1, filteredItems.length - 1);
              renderItems(filteredItems);
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              selectedIndex = Math.max(selectedIndex - 1, 0);
              renderItems(filteredItems);
            } else if (e.key === 'Enter') {
              e.preventDefault();
              if (filteredItems[selectedIndex]) {
                window.location.href = filteredItems[selectedIndex].item.path;
              }
            }
          }
        })();
      </script>
    HTML
  end

end
