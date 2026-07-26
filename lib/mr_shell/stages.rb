# frozen_string_literal: true

module MrShell
  # A stage transforms one enumerable into another. Pipeline only knows this
  # two-method protocol:
  #
  #   stage.call(input) # => enumerable
  #   stage.explain     # => human-readable name
  module Stages
    class Base
      def initialize(name)
        @name = name
      end

      def explain
        @name
      end

      private

      def stream
        Enumerator.new do |output|
          yield output
        rescue StageError, ExternalCommandError
          raise
        rescue StandardError => e
          raise StageError.new(explain, e)
        end
      end
    end

    class Map < Base
      def initialize(function, name: "Map")
        super(name)
        @function = function
      end

      def call(input)
        stream do |output|
          input.each { |record| output << @function.call(record) }
        end
      end
    end

    class Filter < Base
      def initialize(predicate, name: "Filter")
        super(name)
        @predicate = predicate
      end

      def call(input)
        stream do |output|
          input.each do |record|
            output << record if @predicate.call(record)
          end
        end
      end
    end

    class FlatMap < Base
      def initialize(function, name: "FlatMap")
        super(name)
        @function = function
      end

      def call(input)
        stream do |output|
          input.each do |record|
            Array(@function.call(record)).each { |result| output << result }
          end
        end
      end
    end

    class UniqBy < Base
      def initialize(identity, name: "UniqBy")
        super(name)
        @identity = identity
      end

      def call(input)
        stream do |output|
          seen = {}
          input.each do |record|
            identity = @identity.call(record)
            next if seen.key?(identity)

            seen[identity] = true
            output << record
          end
        end
      end
    end

    class SortByKey < Base
      def initialize
        super("SortByKey(in memory)")
      end

      def call(input)
        stream do |output|
          input.to_a.sort_by(&:key).each { |record| output << record }
        end
      end
    end

    class External < Base
      def initialize(command, codec:)
        @command = command
        @codec = codec
        super("External(#{command.join(' ')})")
      end

      def call(input)
        stream do |output|
          ExternalCommand.new(@command).call(input, @codec).each do |record|
            output << record
          end
        end
      end
    end

    class ReduceByKey < Base
      def initialize(specs, verify_sorted: false)
        @specs = Array(specs)
        @verify_sorted = verify_sorted
        names = @specs.map(&:to_s).join(", ")
        super("ReduceByKey(#{names})")
      end

      def call(input)
        raise ConfigurationError, "At least one reducer is required" if @specs.empty?

        stream { |output| reduce(input, output) }
      end

      private

      def reduce(input, output)
        current_key = nil
        accumulators = nil
        previous_key = nil
        have_group = false

        input.each do |record|
          verify_order!(previous_key, record.key) if @verify_sorted && have_group

          if have_group && record.key != current_key
            output << reduced_record(current_key, accumulators)
            accumulators = nil
          end

          unless accumulators
            current_key = record.key
            accumulators = @specs.map(&:initial)
            have_group = true
          end

          accumulators = @specs.each_with_index.map do |spec, index|
            spec.step(accumulators[index], record)
          end
          previous_key = record.key
        end

        output << reduced_record(current_key, accumulators) if have_group
      end

      def reduced_record(key, accumulators)
        values = @specs.each_with_index.map do |spec, index|
          spec.finalize(accumulators[index])
        end
        Record.new(key, values)
      end

      def verify_order!(previous_key, key)
        comparison = previous_key <=> key
        if comparison.nil?
          raise DataError, "Cannot compare keys #{previous_key.inspect} and #{key.inspect}"
        end
        return unless comparison.positive?

        raise DataError,
              "Input is not sorted by key: #{key.inspect} follows #{previous_key.inspect}"
      rescue NoMethodError, ArgumentError => e
        raise DataError,
              "Cannot compare keys #{previous_key.inspect} and #{key.inspect}: #{e.message}"
      end
    end
  end
end
