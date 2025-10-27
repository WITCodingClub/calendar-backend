# app/helpers/background_helper.rb
module BackgroundHelper
  def random_background_url
    # Prefer app/assets images during development/normal asset pipeline usage
    asset_dir = Rails.root.join("app", "assets", "images", "bg")

    # Collect possible files from either location
    candidates = []

    if Dir.exist?(asset_dir)
      candidates += Dir[asset_dir.join("**", "*")].select { |p| File.file?(p) && image_ext?(p) }
    end


    # Safety: if nothing found, return a neutral background or nil
    return nil if candidates.empty?

    # Pick one at random
    picked = candidates.sample

    # Convert filesystem path to a request path
    # If the file is under app/assets, use asset_path so fingerprinting/CDN works
    if picked.start_with?(asset_dir.to_s)
      relative = picked.sub(asset_dir.to_s + "/", "")
      # Use the logical asset path "bg/<file>"
      asset_path(File.join("bg", relative))
    else
      # Otherwise, just return a path relative to public/
      picked.sub(Rails.root.join("public").to_s, "")
    end
  end

  private

  def image_ext?(path)
    ext = File.extname(path).downcase
    %w[.jpg .jpeg .png .gif .webp .avif].include?(ext)
  end
end
