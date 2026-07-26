# frozen_string_literal: true

require "optparse"
require "shellwords"

module MrShell
  class CLI
    USAGE_ERROR = 64
    DATA_ERROR = 65
    SOFTWARE_ERROR = 70

    def self.run(
      arguments,
      input: $stdin,
      output: $stdout,
      error: $stderr,
      framework: Framework.default
    )
      new(
        input: input,
        output: output,
        error: error,
        framework: framework
      ).run(arguments)
    end

    def initialize(input:, output:, error:, framework: Framework.default, registry: nil)
      @input = input
      @output = output
      @error = error
      @framework = framework
      @registry = registry || framework.reducers
    end

    def run(arguments)
      options = default_options
      parser = option_parser(options)
      parser.parse!(arguments)
      return print_and_succeed(parser) if options[:help]
      return print_version if options[:version]
      return print_reducers if options[:list_reducers]

      validate_options!(options, arguments)
      execute(options)
      0
    rescue OptionParser::ParseError, ConfigurationError => e
      @error.puts("mr: #{e.message}")
      @error.puts("Try 'mr --help' for usage.")
      USAGE_ERROR
    rescue DataError => e
      @error.puts("mr: #{e.message}")
      DATA_ERROR
    rescue ExternalCommandError => e
      @error.puts("mr: #{e.message}")
      SOFTWARE_ERROR
    end

    private

    def default_options
      {
        input_format: "tsv",
        output_format: "tsv",
        input_separator: "\t",
        output_separator: "\t",
        steps: []
      }
    end

    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: mr [options] < input > output"
        parser.separator("")
        parser.separator("Streaming MapReduce-style transformations for grouped records.")
        parser.separator("")

        add_transform_options(parser, options)
        add_ordering_options(parser, options)
        add_record_options(parser, options)
        add_format_options(parser, options)
        add_information_options(parser, options)
      end
    end

    def add_transform_options(parser, options)
      parser.on("-r", "--reduce SPEC", "Reduce, e.g. sum[0];avg[1]") do |value|
        options[:steps] << [:reduce, value]
      end
      parser.on("-m RUBY", "--map RUBY", "Map; return [key, *values]") do |value|
        options[:steps] << [:map, value]
      end
      parser.on("-f RUBY", "--filter RUBY", "Keep records when truthy") do |value|
        options[:steps] << [:filter, value]
      end
      parser.on("--flat-map RUBY", "Map one record to many") do |value|
        options[:steps] << [:flat_map, value]
      end
      parser.on("-e RUBY", "--eval RUBY", "Evaluate a Pipeline expression (unsafe)") do |value|
        options[:steps] << [:eval, value]
      end
    end

    def add_ordering_options(parser, options)
      parser.on("-s", "--sort", "Sort records by key using external sort") do
        options[:steps] << [:sort, ["sort"]]
      end
      parser.on("--sort-command COMMAND", "Use a specific external sort command") do |value|
        options[:steps] << [:sort, parse_command(value)]
      end
      parser.on("--check-sorted", "Reject decreasing keys before reduction") do
        options[:check_sorted] = true
      end
    end

    def add_record_options(parser, options)
      parser.on("-k", "--key FIELDS", "Choose zero-based key columns, e.g. 0,2..3") do |value|
        options[:key_fields] = parse_field_selector(value)
      end
      parser.on("-n", "--no-key", "Treat the complete input as one group") do
        options[:no_key] = true
      end
    end

    def add_format_options(parser, options)
      parser.on("-l FORMAT", "--input-format FORMAT", "Input: tsv or jsonl") do |value|
        options[:input_format] = value
      end
      parser.on("-L FORMAT", "--output-format FORMAT", "Output: tsv or jsonl") do |value|
        options[:output_format] = value
      end
      parser.on("-t STRING", "--field-separator STRING", "TSV input separator") do |value|
        options[:input_separator] = unescape_separator(value)
      end
      parser.on("-T STRING", "--output-field-separator STRING", "TSV output separator") do |value|
        options[:output_separator] = unescape_separator(value)
      end
      parser.on("-c TYPES", "--convert TYPES", "TSV column types") do |value|
        options[:types] = value
      end
    end

    def add_information_options(parser, options)
      parser.on("--list-reducers", "List built-in reducers") do
        options[:list_reducers] = true
      end
      parser.on("--explain", "Print the pipeline plan to stderr") { options[:explain] = true }
      parser.on("-v", "--version", "Print the version") { options[:version] = true }
      parser.on("-h", "--help", "Show this help") { options[:help] = true }
    end

    def validate_options!(options, arguments)
      unless arguments.empty?
        raise ConfigurationError, "Unexpected arguments: #{arguments.join(' ')}"
      end

      if options[:key_fields] && options[:no_key]
        raise ConfigurationError, "--key and --no-key cannot be used together"
      end

      has_reducer = options[:steps].any? { |kind, _argument| kind == :reduce }
      return unless options[:check_sorted] && !has_reducer

      raise ConfigurationError, "--check-sorted requires --reduce"
    end

    def execute(options)
      input_codec = @framework.codecs.build(
        options[:input_format],
        input_separator: options[:input_separator],
        types: options[:types]
      )
      output_codec = @framework.codecs.build(
        options[:output_format],
        output_separator: options[:output_separator]
      )

      pipeline = Pipeline.from_lines(@input, input_codec)
      pipeline = select_key(pipeline, options[:key_fields]) if options[:key_fields]
      pipeline = remove_key(pipeline) if options[:no_key]
      pipeline = apply_steps(pipeline, options)
      if options[:explain]
        @error.puts(pipeline.explain)
        @error.puts("→ Output(#{output_codec.name})")
      end

      pipeline.each do |record|
        @output.puts(output_codec.dump(record, include_key: !options[:no_key]))
      end
    end

    def apply_steps(pipeline, options)
      evaluator = RubyEvaluator.new(registry: @registry, framework: @framework)
      externally_grouped = options[:no_key]

      options[:steps].each do |kind, argument|
        case kind
        when :sort
          pipeline = pipeline.through(argument, codec: Codecs::JSONLines.new)
          externally_grouped = true
        when :reduce
          pipeline = pipeline.reduce_by_key(
            @registry.parse(argument),
            verify_sorted: options[:check_sorted] && !externally_grouped
          )
          externally_grouped = false
        when :map
          pipeline = evaluator.map(pipeline, argument)
          externally_grouped = false
        when :filter
          pipeline = evaluator.filter(pipeline, argument)
        when :flat_map
          pipeline = evaluator.flat_map(pipeline, argument)
          externally_grouped = false
        when :eval
          pipeline = evaluator.apply(pipeline, argument)
          externally_grouped = false
        end
      end
      pipeline
    end

    def select_key(pipeline, indices)
      pipeline.map do |record|
        fields = record.to_a
        missing = indices.reject { |index| index >= 0 && index < fields.length }
        unless missing.empty?
          raise DataError,
                "Key field #{missing.first} is missing from a #{fields.length}-field record"
        end

        key_fields = indices.map { |index| fields[index] }
        values = fields.each_with_index.with_object([]) do |(field, index), result|
          result << field unless indices.include?(index)
        end
        Record.new(key_fields.length == 1 ? key_fields.first : key_fields, values)
      end
    end

    def remove_key(pipeline)
      pipeline.map { |record| Record.new(nil, record.to_a) }
    end

    def parse_field_selector(description)
      indices = description.split(",").flat_map do |part|
        token = part.strip
        case token
        when /\A\d+\z/
          token.to_i
        when /\A(\d+)\.\.(\d+)\z/
          first = Regexp.last_match(1).to_i
          last = Regexp.last_match(2).to_i
          raise ConfigurationError, "Descending key range #{token.inspect}" if first > last

          (first..last).to_a
        else
          raise ConfigurationError, "Invalid key field #{token.inspect}"
        end
      end
      raise ConfigurationError, "Key field list cannot be empty" if indices.empty?
      raise ConfigurationError, "Key fields must be unique" unless indices.uniq == indices

      indices
    end

    def unescape_separator(value)
      value.gsub("\\t", "\t")
    end

    def parse_command(value)
      command = Shellwords.split(value)
      raise ConfigurationError, "--sort-command cannot be empty" if command.empty?

      command
    end

    def print_and_succeed(parser)
      @output.puts(parser)
      0
    end

    def print_version
      @output.puts(MrShell::VERSION)
      0
    end

    def print_reducers
      @output.puts(@registry.names.join("\n"))
      0
    end
  end
end
