# frozen_string_literal: true

require "ripper"

module MrShell
  # Alternative ways to turn behavior into a callable object. They share a
  # tiny protocol (name and call) so examples can compare them fairly.
  module EvaluationStrategies
    class Direct
      attr_reader :name

      def initialize(name: "direct block", &function)
        raise ConfigurationError, "Direct strategy requires a block" unless function

        @name = name
        @function = function
      end

      def call(record)
        @function.call(record)
      end
    end

    class Compiled
      attr_reader :name

      def initialize(source, evaluator: RubyEvaluator.new, name: "compile eval once")
        @name = name
        @function = evaluator.compile(source)
      end

      def call(record)
        @function.call(record)
      rescue StandardError => e
        raise EvaluationError, "#{name} failed: #{e.class}: #{e.message}"
      end
    end

    class Repeated
      attr_reader :name

      def initialize(source, name: "eval per record")
        @source = source
        @name = name
      end

      def call(record)
        context = binding
        context.local_variable_set(:record, record)
        context.local_variable_set(:key, record.key)
        context.local_variable_set(:values, record.values)
        context.local_variable_set(:value, record.value)
        eval(@source, context, "(repeated eval)", 1)
      rescue SyntaxError, StandardError => e
        raise EvaluationError, "#{name} failed: #{e.class}: #{e.message}"
      end
    end

    class Context
      class RecordContext
        attr_reader :record

        def initialize(record)
          @record = record
        end

        def key
          record.key
        end

        def values
          record.values
        end

        def value
          record.value
        end

        def evaluate(source)
          instance_eval(source, "(context eval)", 1)
        end
      end

      attr_reader :name

      def initialize(source, name: "instance_eval context")
        @source = source
        @name = name
      end

      def call(record)
        RecordContext.new(record).evaluate(@source)
      rescue SyntaxError, StandardError => e
        raise EvaluationError, "#{name} failed: #{e.class}: #{e.message}"
      end
    end

    class Parsed < Compiled
      def initialize(source, evaluator: RubyEvaluator.new, name: "Ripper + compiled eval")
        raise EvaluationError, "Ripper could not parse the expression" unless Ripper.sexp(source)

        super(source, evaluator: evaluator, name: name)
      end
    end
  end
end
