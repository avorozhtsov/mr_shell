# frozen_string_literal: true

require "json"

module MrShell
  module Codecs
    INTEGER_PATTERN = /\A[+-]?\d+\z/
    FLOAT_PATTERN =
      /\A[+-]?(?:(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?|\d+[eE][+-]?\d+)\z/

    module_function

    def build(name, input_separator: "\t", output_separator: nil, types: nil)
      CodecRegistry.default.build(
        name,
        input_separator: input_separator,
        output_separator: output_separator,
        types: types
      )
    end

    class TSV
      TYPE_ALIASES = {
        "s" => "string",
        "str" => "string",
        "i" => "integer",
        "int" => "integer",
        "f" => "float",
        "bool" => "boolean"
      }.freeze
      TYPES = %w[auto string integer float boolean json].freeze

      attr_reader :input_separator, :output_separator

      def name
        "TSV"
      end

      def initialize(input_separator: "\t", output_separator: "\t", types: nil)
        @input_separator = validate_separator(input_separator, "input")
        @output_separator = validate_separator(output_separator, "output")
        @types = parse_types(types)
      end

      def load(line)
        text = line.to_s.sub(/\r?\n\z/, "")
        fields = text.split(input_separator, -1)
        raise DataError, "A record must contain at least a key" if fields.empty?

        values = fields.each_with_index.map do |field, index|
          convert(field, @types[index] || "auto")
        end
        Record.new(values.first, values.drop(1))
      rescue JSON::ParserError => e
        raise DataError, "Invalid JSON value in TSV record: #{e.message}"
      end

      def dump(record, include_key: true)
        fields = include_key ? record.to_a : record.values
        fields.map { |field| encode(field) }.join(output_separator)
      end

      private

      def validate_separator(separator, kind)
        value = separator.to_s
        if value.empty? || value.include?("\n") || value.include?("\r")
          raise ConfigurationError, "#{kind.capitalize} separator must be non-empty and single-line"
        end

        value
      end

      def parse_types(types)
        return [] unless types

        types.split(/[,:;\s]+/).map do |type|
          normalized = TYPE_ALIASES.fetch(type.downcase, type.downcase)
          unless TYPES.include?(normalized)
            raise ConfigurationError,
                  "Unknown conversion #{type.inspect}; use #{TYPES.join(', ')}"
          end

          normalized
        end
      end

      def convert(field, type)
        case type
        when "auto" then auto_convert(field)
        when "string" then field
        when "integer" then Integer(field, 10)
        when "float" then Float(field)
        when "boolean" then parse_boolean(field)
        when "json" then JSON.parse(field)
        end
      rescue ArgumentError => e
        raise DataError, "Cannot convert #{field.inspect} to #{type}: #{e.message}"
      end

      def auto_convert(field)
        return field.to_i if INTEGER_PATTERN.match?(field)
        return field.to_f if FLOAT_PATTERN.match?(field)
        return JSON.parse(field) if json_literal?(field)

        field
      end

      def json_literal?(field)
        %w[true false null].include?(field) ||
          field.start_with?("[", "{", '"')
      end

      def parse_boolean(field)
        return true if field == "true"
        return false if field == "false"

        raise ArgumentError, "expected true or false"
      end

      def encode(value)
        case value
        when String
          ambiguous_string?(value) ? JSON.generate(value) : value
        when Numeric
          value.to_s
        when true, false, nil, Array, Hash
          JSON.generate(value)
        else
          JSON.generate(value.to_s)
        end
      end

      def ambiguous_string?(value)
        value.empty? ||
          INTEGER_PATTERN.match?(value) ||
          FLOAT_PATTERN.match?(value) ||
          json_literal?(value) ||
          value.include?(output_separator) ||
          value.include?("\n") ||
          value.include?("\r")
      end
    end

    class JSONLines
      def name
        "JSONL"
      end

      def load(line)
        data = JSON.parse(line)
        fields =
          case data
          when Array
            data
          when Hash
            unless data.key?("key") && data["values"].is_a?(Array)
              raise DataError, 'JSON object records require "key" and array "values"'
            end

            [data["key"], *data["values"]]
          else
            raise DataError, "JSON line must be an array or record object"
          end

        raise DataError, "A record must contain at least a key" if fields.empty?

        Record.new(fields.first, fields.drop(1))
      rescue JSON::ParserError => e
        raise DataError, "Invalid JSON line: #{e.message}"
      end

      def dump(record, include_key: true)
        JSON.generate(include_key ? record.to_a : record.values)
      end
    end
  end
end
