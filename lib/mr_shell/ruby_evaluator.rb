# frozen_string_literal: true

module MrShell
  # Compiles user-supplied Ruby into pipeline stages.
  #
  # This class is intentionally powerful and intentionally unsafe. Keeping
  # evaluation in one small class makes both facts visible and testable.
  class RubyEvaluator
    def initialize(registry: nil, framework: Framework.default, filename: "(mr eval)")
      @framework = framework
      @registry = registry || framework.reducers
      @filename = filename
    end

    # Compile once, then call the resulting Proc for every record. The
    # expression can use record, key, values, and value.
    def compile(source)
      # The generated source has this shape:
      # lambda do |record|
      #   key = record.key
      #   values = record.values
      #   value = record.value
      #   <user source>
      # end
      eval(
        <<~RUBY,
          lambda do |record|
            key = record.key
            values = record.values
            value = record.value
            #{source}
          end
        RUBY
        binding,
        @filename,
        1
      )
    rescue SyntaxError => e
      raise EvaluationError, "Cannot compile Ruby expression: #{e.message}"
    end

    def map(pipeline, source)
      function = compile(source)
      pipeline.map(label: stage_name("Map", source)) do |record|
        record_from(call(function, record))
      end
    end

    def filter(pipeline, source)
      predicate = compile(source)
      pipeline.filter(label: stage_name("Filter", source)) do |record|
        call(predicate, record)
      end
    end

    def flat_map(pipeline, source)
      function = compile(source)
      pipeline.flat_map(label: stage_name("FlatMap", source)) do |record|
        results = call(function, record)
        unless results.respond_to?(:each)
          raise EvaluationError, "Flat-map expression must return an enumerable"
        end

        results.map { |result| record_from(result) }
      end
    end

    # Evaluate a complete pipeline expression. The source can use pipeline and
    # registry, and must return a Pipeline.
    def apply(pipeline, source)
      context = binding
      context.local_variable_set(:pipeline, pipeline)
      context.local_variable_set(:registry, @registry)
      context.local_variable_set(:framework, @framework)
      result = eval(source, context, @filename, 1)
      return result if result.is_a?(Pipeline)

      raise EvaluationError, "--eval must return an MrShell::Pipeline"
    rescue SyntaxError, StandardError => e
      raise_evaluation_error(e)
    end

    private

    def stage_name(kind, source)
      compact = source.gsub(/\s+/, " ").strip
      compact = "#{compact[0, 37]}..." if compact.length > 40
      "#{kind}(Ruby: #{compact})"
    end

    def call(function, record)
      function.call(record)
    rescue StandardError => e
      raise_evaluation_error(e)
    end

    def record_from(result)
      return result if result.is_a?(Record)
      return Record.new(result.first, result.drop(1)) if result.is_a?(Array) && !result.empty?

      raise EvaluationError,
            "Map expression must return a Record or a non-empty record array"
    end

    def raise_evaluation_error(error)
      raise error if error.is_a?(EvaluationError)

      raise EvaluationError, "Ruby evaluation failed: #{error.class}: #{error.message}"
    end
  end
end
