# frozen_string_literal: true

module MrShell
  # Small executable specifications for framework extension protocols.
  module Contracts
    module_function

    def verify_codec(codec, records:)
      require_methods(codec, :name, :load, :dump)
      records.each do |record|
        loaded = codec.load("#{codec.dump(record)}\n")
        next if loaded == record

        raise ContractError,
              "#{codec.name} does not round-trip #{record.inspect}: got #{loaded.inspect}"
      end
      true
    end

    def verify_reducer(definition, values:)
      require_methods(definition, :name, :initial, :step, :finalize)
      first = definition.initial
      second = definition.initial
      if mutable?(first) && first.equal?(second)
        raise ContractError, "#{definition.name} reuses a mutable initial accumulator"
      end

      accumulator = values.reduce(first) do |current, value|
        definition.step(current, value)
      end
      definition.finalize(accumulator)
      true
    end

    def verify_stage(stage, input:)
      require_methods(stage, :explain, :call)
      result = stage.call(input)
      unless result.respond_to?(:each)
        raise ContractError, "#{stage.explain} must return an enumerable"
      end

      result.to_a
      true
    end

    def require_methods(object, *methods)
      missing = methods.reject { |method| object.respond_to?(method) }
      return if missing.empty?

      raise ContractError,
            "#{object.class} is missing required method(s): #{missing.join(', ')}"
    end
    private_class_method :require_methods

    def mutable?(object)
      object.is_a?(Array) || object.is_a?(Hash) || object.is_a?(String)
    end
    private_class_method :mutable?
  end
end
