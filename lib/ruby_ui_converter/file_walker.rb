# frozen_string_literal: true

module RubyUIConverter
  # Finds template files (.erb, .haml) under a path (recursively for
  # directories).
  class FileWalker
    # Keep in sync with RubyUIConverter::FORMATS.
    GLOB = "**/*.{erb,haml}"

    def initialize(path)
      @path = path
    end

    def template_files
      if File.directory?(@path)
        Dir.glob(File.join(@path, GLOB)).select { |f| File.file?(f) }.sort
      elsif File.file?(@path) && RubyUIConverter.format_for(@path)
        [@path]
      else
        []
      end
    end

    # Kept for backwards compatibility: only the .erb templates.
    def erb_files
      template_files.select { |f| RubyUIConverter.format_for(f) == :erb }
    end
  end
end
