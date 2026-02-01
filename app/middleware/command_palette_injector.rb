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
    begin
      new_response = inject_script(response)
      puts "Script injected. Response size: #{new_response.bytesize}"

      # Update content length
      headers.delete("Content-Length") # Remove old content length, let Rack recalculate

      [status, headers, [new_response]]
    rescue StandardError => e
      puts "ERROR injecting script: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      [status, headers, response]
    end
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
    parts = []
    response.each { |part| parts << part }
    response.close if response.respond_to?(:close)
    parts.join
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
            paletteContainer.style.display = 'flex';
            const input = paletteContainer.querySelector('input');
            if (input) {
              input.value = '';
              input.focus();
              showAllItems();
            }
          }

          function closePalette() {
            if (paletteContainer) {
              paletteContainer.style.display = 'none';
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
            paletteContainer.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.6);backdrop-filter:blur(8px);display:none;align-items:flex-start;justify-content:center;padding-top:15vh;z-index:99999';

            // Click backdrop to close
            paletteContainer.addEventListener('click', function(e) {
              if (e.target === paletteContainer) {
                closePalette();
              }
            });

            // Inner modal
            const modal = document.createElement('div');
            modal.style.cssText = 'background:white;border-radius:12px;box-shadow:0 25px 50px -12px rgba(0,0,0,0.25);width:100%;max-width:42rem;margin:0 1rem;overflow:hidden;border:1px solid #e5e7eb';
            modal.addEventListener('click', function(e) {
              e.stopPropagation();
            });

            // Search input
            const searchContainer = createSearchInput();
            modal.appendChild(searchContainer);

            // Results container
            const resultsContainer = document.createElement('div');
            resultsContainer.id = 'palette-results';
            resultsContainer.style.cssText = 'max-height:24rem;overflow-y:auto';
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
            container.style.position = 'relative';

            const iconDiv = document.createElement('div');
            iconDiv.style.cssText = 'position:absolute;top:0;bottom:0;left:0;padding-left:1rem;display:flex;align-items:center;pointer-events:none';
            const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            icon.setAttribute('width', '20');
            icon.setAttribute('height', '20');
            icon.setAttribute('fill', 'none');
            icon.setAttribute('stroke', '#9ca3af');
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
            input.style.cssText = 'width:100%;padding:1rem 1rem 1rem 3rem;font-size:1rem;border:0;border-bottom:1px solid #e5e7eb;outline:none';

            input.addEventListener('input', handleSearch);
            input.addEventListener('keydown', handleKeyboard);

            container.appendChild(iconDiv);
            container.appendChild(input);
            return container;
          }

          function createFooter() {
            const footer = document.createElement('div');
            footer.style.cssText = 'padding:0.75rem 1rem;background:#f9fafb;border-top:1px solid #e5e7eb;display:flex;align-items:center;justify-content:space-between;font-size:0.75rem;color:#6b7280';

            const leftHints = document.createElement('div');
            leftHints.style.cssText = 'display:flex;align-items:center;gap:0.75rem';

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
            hint.style.cssText = 'display:flex;align-items:center;gap:0.25rem';

            const kbd = document.createElement('kbd');
            kbd.style.cssText = 'padding:0.25rem 0.5rem;background:white;border:1px solid #d1d5db;border-radius:0.25rem;font-size:0.75rem;font-weight:500;box-shadow:0 1px 2px 0 rgba(0,0,0,0.05)';
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
              noResults.style.cssText = 'padding:2rem 1rem;text-align:center;font-size:0.875rem;color:#6b7280';
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
            const isSelected = index === selectedIndex;
            itemDiv.style.cssText = 'padding:0.625rem 1rem;cursor:pointer;border-left:2px solid ' + (isSelected ? '#b91c1c' : 'transparent') + ';background:' + (isSelected ? '#fef2f2' : 'white') + ';transition:background 0.15s';

            itemDiv.addEventListener('mouseenter', function() {
              if (!isSelected) itemDiv.style.background = '#f9fafb';
            });
            itemDiv.addEventListener('mouseleave', function() {
              if (!isSelected) itemDiv.style.background = 'white';
            });
            itemDiv.addEventListener('click', function() {
              window.location.href = item.path;
            });

            const wrapper = document.createElement('div');
            wrapper.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:0.75rem';

            const left = document.createElement('div');
            left.style.cssText = 'flex:1;min-width:0';

            const title = document.createElement('div');
            title.style.cssText = 'font-weight:500;font-size:0.875rem;color:#111827;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
            title.textContent = item.title;
            left.appendChild(title);

            if (item.description) {
              const desc = document.createElement('div');
              desc.style.cssText = 'font-size:0.75rem;color:#6b7280;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-top:0.125rem';
              desc.textContent = item.description;
              left.appendChild(desc);
            }

            const right = document.createElement('span');
            right.style.cssText = 'font-size:0.75rem;color:#9ca3af;text-transform:uppercase;flex-shrink:0';
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
