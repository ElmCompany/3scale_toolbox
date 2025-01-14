module ThreeScaleToolbox
  module ResourceReader
    ##
    # Load resource from different types of sources.
    # Supported types are: file, URL, stdin
    # Loaded content is returned
    def load_resource(resource)
      # Json format is parsed as well
      YAML.safe_load(read_content(resource))
    rescue Psych::SyntaxError => e
      raise ThreeScaleToolbox::Error, "JSON/YAML validation failed: #{e.message}"
    end

    ##
    # Reads resources from different types of sources.
    # Supported types are: file, URL, stdin
    # Resource raw content is returned
    def read_content(resource)
      case resource
      when '-'
        method(:read_stdin)
      when /\A#{URI::DEFAULT_PARSER.make_regexp}\z/
        method(:read_url)
      when StringIO
        method(:read_stringio)
      else
        method(:read_file)
      end.call(resource)
    end

    # Detect format from file extension
    def read_file(filename)
      raise ThreeScaleToolbox::Error, "File not found: #{filename} " unless File.file?(filename)
      raise ThreeScaleToolbox::Error, "File not readable: #{filename} " unless File.readable?(filename)

      File.read(filename)
    end

    def read_stdin(_resource)
      STDIN.read
    end

    def read_url(resource)
      Net::HTTP.get(URI.parse(resource))
    end

    def read_stringio(resource)
      resource.string
    end
  end
end
