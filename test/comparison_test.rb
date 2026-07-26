# frozen_string_literal: true

require_relative "test_helper"

class ComparisonTest < Minitest::Test
  def test_report_verifies_and_measures_each_approach
    comparison = MrShell::Comparison.new
      .add("array") { [1, 2, 3] }
      .add("lazy") { [1, 2, 3].lazy }
    output = StringIO.new

    measurements = comparison.report(output: output)

    assert_equal %w[array lazy], measurements.map(&:name)
    assert(measurements.all? { |measurement| measurement.items == 3 })
    assert(measurements.all? { |measurement| measurement.total_seconds >= 0 })
    assert(measurements.all? { |measurement| measurement.first_seconds >= 0 })
    assert(measurements.all? { |measurement| measurement.allocations.positive? })
    assert_match(/peak KiB/, output.string)
  end

  def test_comparison_refuses_to_benchmark_different_results
    comparison = MrShell::Comparison.new
      .add("correct") { [1, 2] }
      .add("wrong") { [1, 3] }

    error = assert_raises(MrShell::ContractError) { comparison.measurements }
    assert_match(/wrong disagrees with correct/, error.message)
  end

  def test_comparison_requires_two_approaches
    comparison = MrShell::Comparison.new.add("lonely") { [1] }

    assert_raises(MrShell::ContractError) { comparison.verify! }
  end
end
