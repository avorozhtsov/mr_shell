# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "mr_shell"

module MrShellExamples
  # Compare direct Ruby, compiling eval once, and evaluating source for every
  # record. The framework deliberately uses the middle approach.
  module CompareEval
    EXPRESSION = "[key.upcase, value * 2]"

    module_function

    def direct(records)
      run_strategy(
        records,
        MrShell::EvaluationStrategies::Direct.new do |record|
          [record.key.upcase, record.value * 2]
        end
      )
    end

    def compiled(records)
      run_strategy(records, MrShell::EvaluationStrategies::Compiled.new(EXPRESSION))
    end

    def evaluated_each_time(records)
      run_strategy(records, MrShell::EvaluationStrategies::Repeated.new(EXPRESSION))
    end

    def context(records)
      run_strategy(records, MrShell::EvaluationStrategies::Context.new(EXPRESSION))
    end

    def parsed(records)
      run_strategy(records, MrShell::EvaluationStrategies::Parsed.new(EXPRESSION))
    end

    def run_strategy(records, strategy)
      records.map { |record| strategy.call(record) }
    end

    def verify(records)
      comparison(records).verify!
    end

    def run(size: 100_000, output: $stdout)
      records = Array.new(size) { |index| MrShell::Record.new("key-#{index}", [index]) }
      output.puts("Comparing evaluation strategies for #{size} records.")
      comparison(records).report(output: output)
    end

    def comparison(records)
      MrShell::Comparison.new
        .add("direct block") { direct(records) }
        .add("compile eval once") { compiled(records) }
        .add("eval per record") { evaluated_each_time(records) }
        .add("instance_eval") { context(records) }
        .add("Ripper + compile") { parsed(records) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  size = Integer(ENV.fetch("SIZE", "100000"), 10)
  MrShellExamples::CompareEval.run(size: size)
end
