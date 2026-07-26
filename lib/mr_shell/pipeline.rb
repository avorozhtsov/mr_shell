# frozen_string_literal: true

module MrShell
  class Pipeline
    include Enumerable

    attr_reader :stages

    def self.from_lines(io, codec)
      source = Enumerator.new do |output|
        io.each_line do |line|
          next if line.strip.empty?

          output << codec.load(line)
        rescue StageError
          raise
        rescue StandardError => e
          raise StageError.new("Input(#{codec.name})", e)
        end
      end
      new(source, source_name: "Input(#{codec.name})")
    end

    def initialize(source, source_name: "Input(Enumerable)", stages: [])
      @source = source
      @source_name = source_name
      @stages = stages.freeze
    end

    def each(&consumer)
      return enum_for(:each) unless consumer

      stream = stages.reduce(@source) { |input, stage| stage.call(input) }
      stream.each { |record| consumer.call(record) }
      self
    end

    def add_stage(stage)
      unless stage.respond_to?(:call) && stage.respond_to?(:explain)
        raise ConfigurationError, "A stage must respond to call(input) and explain"
      end

      Pipeline.new(
        @source,
        source_name: @source_name,
        stages: stages + [stage]
      )
    end

    def map(label: "Map", &transform)
      return enum_for(:map, label: label) unless transform

      add_stage(Stages::Map.new(transform, name: label))
    end

    def filter(label: "Filter", &predicate)
      return enum_for(:filter, label: label) unless predicate

      add_stage(Stages::Filter.new(predicate, name: label))
    end
    alias select filter

    def flat_map(label: "FlatMap", &transform)
      return enum_for(:flat_map, label: label) unless transform

      add_stage(Stages::FlatMap.new(transform, name: label))
    end

    def uniq_by(label: "UniqBy", &identity)
      return enum_for(:uniq_by, label: label) unless identity

      add_stage(Stages::UniqBy.new(identity, name: label))
    end

    def sort_by_key
      add_stage(Stages::SortByKey.new)
    end

    def through(command, codec:)
      add_stage(Stages::External.new(command, codec: codec))
    end

    def reduce_by_key(specs, verify_sorted: false)
      add_stage(Stages::ReduceByKey.new(specs, verify_sorted: verify_sorted))
    end

    def explain
      ([@source_name] + stages.map { |stage| "→ #{stage.explain}" }).join("\n")
    end
  end
end
