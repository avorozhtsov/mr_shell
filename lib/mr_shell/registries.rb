# frozen_string_literal: true

module MrShell
  # Registries turn framework extension into data: a name points to a factory.
  class FactoryRegistry
    def initialize(kind)
      @kind = kind
      @factories = {}
    end

    def register(name, *aliases, &factory)
      raise ConfigurationError, "#{@kind} factory requires a block" unless factory

      ([name] + aliases).each do |registered_name|
        key = normalize(registered_name)
        if @factories.key?(key)
          raise ConfigurationError, "#{@kind} #{key.inspect} is already registered"
        end

        @factories[key] = factory
      end
      self
    end

    def build(name, **options)
      factory = @factories.fetch(normalize(name)) do
        raise ConfigurationError,
              "Unknown #{@kind.downcase} #{name.inspect}; available: #{names.join(', ')}"
      end
      factory.call(**options)
    end

    def names
      @factories.keys.sort
    end

    private

    def normalize(name)
      name.to_s.downcase.tr("-", "_")
    end
  end

  class CodecRegistry < FactoryRegistry
    def self.default
      new
        .register("tsv", "simple") do |input_separator: "\t", output_separator: nil, types: nil|
          Codecs::TSV.new(
            input_separator: input_separator,
            output_separator: output_separator || input_separator,
            types: types
          )
        end
        .register("jsonl", "json") do |types: nil, **_unused|
          raise ConfigurationError, "--convert is only available for TSV input" if types

          Codecs::JSONLines.new
        end
    end

    def initialize
      super("Codec")
    end
  end

  class StageRegistry < FactoryRegistry
    def self.default
      new
        .register("map") do |function:, name: "Map"|
          Stages::Map.new(function, name: name)
        end
        .register("filter") do |predicate:, name: "Filter"|
          Stages::Filter.new(predicate, name: name)
        end
        .register("flat_map") do |function:, name: "FlatMap"|
          Stages::FlatMap.new(function, name: name)
        end
        .register("uniq_by") do |identity:, name: "UniqBy"|
          Stages::UniqBy.new(identity, name: name)
        end
        .register("sort_by_key") { Stages::SortByKey.new }
        .register("external") do |command:, codec:|
          Stages::External.new(command, codec: codec)
        end
        .register("reduce_by_key") do |specs:, verify_sorted: false|
          Stages::ReduceByKey.new(specs, verify_sorted: verify_sorted)
        end
    end

    def initialize
      super("Stage")
    end
  end

  class Framework
    attr_reader :reducers, :codecs, :stages

    def self.default
      new(
        reducers: ReducerRegistry.default,
        codecs: CodecRegistry.default,
        stages: StageRegistry.default
      )
    end

    def initialize(reducers:, codecs:, stages:)
      @reducers = reducers
      @codecs = codecs
      @stages = stages
    end
  end
end
