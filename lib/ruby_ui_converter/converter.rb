# frozen_string_literal: true

require "fileutils"

module RubyUIConverter
  # Orchestrates the conversion of an entire directory (or single file).
  class Converter
    Result = Struct.new(:source, :output, :status, :error, :code, keyword_init: true)

    def initialize(path, config: Configuration.new)
      @path = path
      @config = config
    end

    # The namespace root. Precedence: explicit config.root, then the nearest
    # `app/views` ancestor (Rails convention — keeps generated constants
    # matching the Zeitwerk path mapping no matter which subfolder was
    # converted), then the directory the user pointed at.
    def root
      @root ||=
        if @config.root
          File.expand_path(@config.root)
        else
          base =
            if File.directory?(@path)
              File.expand_path(@path)
            else
              File.dirname(File.expand_path(@path))
            end
          conventional_root(base) || base
        end
    end

    def run
      FileWalker.new(@path).erb_files.map { |file| convert_file(file) }
    end

    private

    # Nearest ancestor (including dir itself) that is a Rails `app/views`
    # directory, or nil when the path is not inside one.
    def conventional_root(dir)
      current = dir
      loop do
        return current if File.basename(current) == "views" &&
                          File.basename(File.dirname(current)) == "app"

        parent = File.dirname(current)
        return nil if parent == current

        current = parent
      end
    end

    def convert_file(file)
      file = File.expand_path(file)
      template = Template.new(path: file, root: root, config: @config)
      code = template.render
      output = template.output_path

      if @config.dry_run
        return Result.new(source: file, output: output, status: :previewed, code: code)
      end

      if File.exist?(output) && !@config.force
        return Result.new(source: file, output: output, status: :skipped, code: code)
      end

      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, code)
      Result.new(source: file, output: output, status: :written, code: code)
    rescue StandardError => e
      Result.new(source: file, output: nil, status: :error, error: e)
    end
  end
end
