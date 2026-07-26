# frozen_string_literal: true

module MrShell
  class ReducerDefinition
    attr_reader :name

    def initialize(name, needs_value:, initial:, step:, finalize:)
      @name = name
      @needs_value = needs_value
      @initial = initial
      @step = step
      @finalize = finalize
    end

    def needs_value?
      @needs_value
    end

    def initial
      @initial.call
    end

    def step(accumulator, value)
      @step.call(accumulator, value)
    end

    def finalize(accumulator)
      @finalize.call(accumulator)
    end
  end

  class ReducerSpec
    attr_reader :definition, :field

    def initialize(definition, field = nil)
      @definition = definition
      @field = field
      return unless field && !definition.needs_value?

      raise ConfigurationError, "#{definition.name} does not accept a field selector"
    end

    def name
      definition.name
    end

    def to_s
      field.nil? ? name : "#{name}[#{field}]"
    end

    def initial
      definition.initial
    end

    def step(accumulator, record)
      value = extract_value(record)
      definition.step(accumulator, value)
    rescue IndexError
      raise DataError,
            "Reducer #{name}[#{field}] cannot read a record with " \
            "#{record.values.length} value field(s)"
    rescue TypeError, ArgumentError, NoMethodError => e
      raise DataError, "Reducer #{name} rejected #{value.inspect}: #{e.message}"
    end

    def finalize(accumulator)
      definition.finalize(accumulator)
    end

    private

    def extract_value(record)
      return nil unless definition.needs_value?
      return record.values.fetch(field) if field
      return record.values.first if record.values.length == 1

      raise DataError,
            "Reducer #{name} needs a field selector for records with " \
            "#{record.values.length} value fields"
    end
  end

  class ReducerRegistry
    SPEC_PATTERN = /\A([A-Za-z][A-Za-z0-9_-]*)(?:\[(-?\d+)\])?\z/

    attr_reader :definitions

    def self.default
      registry = new
      identity = ->(value) { value }

      registry.register(
        "sum",
        initial: -> { 0 },
        step: ->(acc, value) { acc + numeric(value) },
        finalize: identity
      )
      registry.register(
        "prod",
        initial: -> { 1 },
        step: ->(acc, value) { acc * numeric(value) },
        finalize: identity
      )
      registry.register(
        "min",
        initial: -> { nil },
        step: ->(acc, value) { acc.nil? || value < acc ? value : acc },
        finalize: identity
      )
      registry.register(
        "max",
        initial: -> { nil },
        step: ->(acc, value) { acc.nil? || value > acc ? value : acc },
        finalize: identity
      )
      registry.register(
        "count",
        needs_value: false,
        initial: -> { 0 },
        step: ->(acc, _value) { acc + 1 },
        finalize: identity
      )
      registry.register(
        "avg",
        initial: -> { [0, 0.0] },
        step: lambda { |acc, value|
          number = numeric(value)
          [acc[0] + 1, acc[1] + number]
        },
        finalize: ->(acc) { acc[0].zero? ? nil : acc[1] / acc[0] }
      )
      registry.register(
        "stddev",
        initial: -> { [0, 0.0, 0.0] },
        step: method(:welford_step),
        finalize: method(:population_standard_deviation)
      )
      registry.register(
        "relative_stddev",
        initial: -> { [0, 0.0, 0.0] },
        step: method(:welford_step),
        finalize: lambda { |acc|
          deviation = population_standard_deviation(acc)
          deviation && !acc[1].zero? ? deviation / acc[1].abs : nil
        }
      )
      registry.register(
        "collect",
        initial: -> { [] },
        step: lambda { |acc, value|
          acc << value
          acc
        },
        finalize: identity
      )
      registry.register(
        "uniq",
        initial: -> { {} },
        step: lambda { |acc, value|
          acc[value] = true
          acc
        },
        finalize: ->(acc) { acc.keys }
      )
      registry.register(
        "frequency",
        initial: -> { Hash.new(0) },
        step: lambda { |acc, value|
          acc[value] += 1
          acc
        },
        finalize: ->(acc) { acc.to_h }
      )

      registry.alias_name("join", "collect")
      registry.alias_name("freq", "frequency")
      registry.alias_name("sigma", "stddev")
      registry.alias_name("rsigma", "relative_stddev")
      registry
    end

    def self.numeric(value)
      return value if value.is_a?(Numeric)

      raise TypeError, "expected a number"
    end

    def self.welford_step(accumulator, value)
      number = numeric(value).to_f
      count, mean, squared_distance = accumulator
      count += 1
      delta = number - mean
      mean += delta / count
      squared_distance += delta * (number - mean)
      [count, mean, squared_distance]
    end

    def self.population_standard_deviation(accumulator)
      count, _mean, squared_distance = accumulator
      count.zero? ? nil : Math.sqrt(squared_distance / count)
    end

    def initialize
      @definitions = {}
    end

    def register(name, initial:, step:, finalize:, needs_value: true)
      normalized = normalize_name(name)
      if definitions.key?(normalized)
        raise ConfigurationError, "Reducer #{normalized.inspect} is already registered"
      end

      definitions[normalized] = ReducerDefinition.new(
        normalized,
        needs_value: needs_value,
        initial: initial,
        step: step,
        finalize: finalize
      )
      self
    end

    def alias_name(alias_name, target_name)
      target = fetch(target_name)
      definitions[normalize_name(alias_name)] = target
      self
    end

    def fetch(name)
      normalized = normalize_name(name)
      definitions.fetch(normalized) do
        raise ConfigurationError,
              "Unknown reducer #{name.inspect}; available reducers: #{names.join(', ')}"
      end
    end

    def names
      definitions.keys.sort
    end

    def parse(description)
      parts = split_description(description.to_s)
      raise ConfigurationError, "Reducer description cannot be empty" if parts.empty?

      parts.map do |part|
        match = SPEC_PATTERN.match(part)
        unless match
          raise ConfigurationError,
                "Invalid reducer #{part.inspect}; expected NAME or NAME[FIELD]"
        end
        ReducerSpec.new(fetch(match[1]), match[2]&.to_i)
      end
    end

    private

    def normalize_name(name)
      name.to_s.downcase.tr("-", "_")
    end

    def split_description(description)
      parts = []
      current = +""
      bracket_depth = 0

      description.each_char do |character|
        bracket_depth += 1 if character == "["
        bracket_depth -= 1 if character == "]"

        if [";", ","].include?(character) && bracket_depth.zero?
          parts << current.strip unless current.strip.empty?
          current.clear
        else
          current << character
        end
      end
      parts << current.strip unless current.strip.empty?
      parts
    end
  end
end
