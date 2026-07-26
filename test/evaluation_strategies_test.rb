# frozen_string_literal: true

require_relative "test_helper"

class EvaluationStrategiesTest < Minitest::Test
  EXPRESSION = "[key.upcase, value * 2]"

  def setup
    @record = MrShell::Record.new("a", [3])
    @expected = ["A", 6]
  end

  def test_all_strategies_share_the_same_result_and_protocol
    strategies = [
      MrShell::EvaluationStrategies::Direct.new do |record|
        [record.key.upcase, record.value * 2]
      end,
      MrShell::EvaluationStrategies::Compiled.new(EXPRESSION),
      MrShell::EvaluationStrategies::Repeated.new(EXPRESSION),
      MrShell::EvaluationStrategies::Context.new(EXPRESSION),
      MrShell::EvaluationStrategies::Parsed.new(EXPRESSION)
    ]

    strategies.each do |strategy|
      refute_empty strategy.name
      assert_equal @expected, strategy.call(@record), strategy.name
    end
  end

  def test_parsed_strategy_rejects_invalid_syntax_before_compilation
    error = assert_raises(MrShell::EvaluationError) do
      MrShell::EvaluationStrategies::Parsed.new("key.")
    end

    assert_match(/Ripper/, error.message)
  end

  def test_direct_strategy_requires_a_block
    assert_raises(MrShell::ConfigurationError) do
      MrShell::EvaluationStrategies::Direct.new
    end
  end
end
