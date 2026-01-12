#!/usr/bin/env ruby
# frozen_string_literal: true

require "active_support/core_ext/hash/deep_merge"
require "fileutils"
require "yaml"

PATH = "./doc/openapi.yaml"

if ENV["MOVE_TMP_FILES"]
  FileUtils.mv(Dir.glob("./tmp/openapi?*.yaml"), "./doc/")
end

content = {}
Dir.glob("./doc/openapi?*.yaml").each do |filename|
  content.deep_merge!(YAML.safe_load_file(filename))
end
# Sort endpoints alphabetically and remove duplicate endpoints
content["paths"] = content["paths"].sort.uniq(&:first).to_h if content["paths"]
File.write(PATH, YAML.dump(content))
FileUtils.cp(PATH, "./tmp/openapi#{ENV['CI_NODE_INDEX']}.yaml") if ENV["CI_NODE_INDEX"]
