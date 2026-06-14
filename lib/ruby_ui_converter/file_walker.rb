# frozen_string_literal: true

module RubyUIConverter
  # Finds .erb files under a path (recursively for directories).
  class FileWalker
    ERB_GLOB = "**/*.erb"

    def initialize(path)
      @path = path
    end

    def erb_files
      if File.directory?(@path)
        Dir.glob(File.join(@path, ERB_GLOB)).select { |f| File.file?(f) }.sort
      elsif File.file?(@path) && @path.end_with?(".erb")
        [@path]
      else
        []
      end
    end
  end
end
