# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  def test_help_and_version
    status, output, error = run_cli("--help")
    assert_equal 0, status
    assert_match(/Usage: mr/, output)
    assert_empty error

    status, output, = run_cli("--version")
    assert_equal 0, status
    assert_equal "#{MrShell::VERSION}\n", output
  end

  def test_grouped_sum
    status, output, error = run_cli(
      "--reduce", "sum",
      input: "a\t1\na\t2\nb\t3\n"
    )

    assert_equal 0, status
    assert_equal "a\t3\nb\t3\n", output
    assert_empty error
  end

  def test_external_sort_and_multiple_reducers
    status, output, = run_cli(
      "--sort", "--reduce", "sum[0];avg[1]",
      input: "b\t4\t20\na\t3\t30\na\t1\t10\n"
    )

    assert_equal 0, status
    assert_equal "a\t4\t20.0\nb\t4\t20.0\n", output
  end

  def test_eval_stages_are_applied_in_command_line_order
    status, output, error = run_cli(
      "--flat-map", "key.split.map { |word| [word, value] }",
      "--filter", 'key != "ignored"',
      "--sort",
      "--reduce", "sum",
      "--map", "[key.upcase, value]",
      input: "red blue\t2\nblue\t1\nignored\t10\n"
    )

    assert_equal 0, status
    assert_equal "BLUE\t3\nRED\t2\n", output
    assert_empty error
  end

  def test_full_pipeline_eval_exposes_registry
    status, output, = run_cli(
      "--eval", 'pipeline.reduce_by_key(registry.parse("sum"))',
      input: "a\t1\na\t2\n"
    )

    assert_equal 0, status
    assert_equal "a\t3\n", output
  end

  def test_full_eval_can_use_a_custom_framework_stage
    framework = MrShell::Framework.default
    framework.stages.register("double") do
      MrShell::Stages::Map.new(
        ->(record) { MrShell::Record.new(record.key, [record.value * 2]) },
        name: "Double"
      )
    end
    output = StringIO.new
    error = StringIO.new

    status = MrShell::CLI.run(
      ["--eval", 'pipeline.add_stage(framework.stages.build("double"))'],
      input: StringIO.new("a\t3\n"),
      output: output,
      error: error,
      framework: framework
    )

    assert_equal 0, status
    assert_equal "a\t6\n", output.string
    assert_empty error.string
  end

  def test_explain_prints_the_plan_without_mixing_it_with_data
    status, output, error = run_cli(
      "--map", "[key.upcase, value]",
      "--sort",
      "--reduce", "sum",
      "--explain",
      input: "a\t1\n"
    )

    assert_equal 0, status
    assert_equal "A\t1\n", output
    assert_match(/Input\(TSV\)/, error)
    assert_match(/Map\(Ruby:/, error)
    assert_match(/External\(sort\)/, error)
    assert_match(/ReduceByKey\(sum\)/, error)
    assert_match(/Output\(TSV\)/, error)
  end

  def test_eval_failure_is_a_data_error
    status, _output, error = run_cli(
      "--map", "missing_method",
      input: "a\t1\n"
    )

    assert_equal MrShell::CLI::DATA_ERROR, status
    assert_match(/Ruby evaluation failed/, error)
  end

  def test_external_sort_groups_numeric_keys_when_sorted_check_is_requested
    status, output, = run_cli(
      "--sort", "--check-sorted", "--reduce", "sum",
      input: "2\t1\n10\t3\n2\t2\n"
    )

    assert_equal 0, status
    assert_equal "10\t3\n2\t3\n", output
  end

  def test_no_key_counts_all_records
    status, output, = run_cli(
      "--no-key", "--reduce", "count",
      input: "a\t1\nb\t2\n"
    )

    assert_equal 0, status
    assert_equal "2\n", output
  end

  def test_key_selection_uses_complete_record_columns
    status, output, = run_cli(
      "--key", "0,2", "--reduce", "sum[0]",
      input: "a\t1\tx\na\t2\tx\n"
    )

    assert_equal 0, status
    assert_equal "[\"a\",\"x\"]\t3\n", output
  end

  def test_json_lines_input_and_output
    status, output, = run_cli(
      "--input-format", "jsonl",
      "--output-format", "jsonl",
      "--reduce", "sum",
      input: "[\"a\",1]\n[\"a\",2]\n"
    )

    assert_equal 0, status
    assert_equal "[\"a\",3]\n", output
  end

  def test_invalid_option_returns_usage_error
    status, _output, error = run_cli("--code", "puts(:unsafe)")

    assert_equal MrShell::CLI::USAGE_ERROR, status
    assert_match(/invalid option/, error)
  end

  def test_bad_data_returns_data_error
    status, _output, error = run_cli(
      "--convert", "integer",
      input: "not-an-integer\n"
    )

    assert_equal MrShell::CLI::DATA_ERROR, status
    assert_match(/Cannot convert/, error)
  end

  def test_complete_executable
    command = [RbConfig.ruby, File.expand_path("../bin/mr", __dir__), "--reduce", "sum"]
    output, error, status = Open3.capture3(*command, stdin_data: "a\t1\na\t2\n")

    assert status.success?, error
    assert_equal "a\t3\n", output
  end

  def test_word_count_matches_the_golden_file
    fixtures = File.expand_path("fixtures", __dir__)
    input = File.read(File.join(fixtures, "word_count_input.tsv"))
    expected = File.read(File.join(fixtures, "word_count_expected.tsv"))
    status, output, error = run_cli(
      "--flat-map", "key.split.map { |word| [word, value] }",
      "--sort",
      "--reduce", "sum",
      input: input
    )

    assert_equal 0, status
    assert_equal expected, output
    assert_empty error
  end

  private

  def run_cli(*arguments, input: "")
    output = StringIO.new
    error = StringIO.new
    status = MrShell::CLI.run(
      arguments,
      input: StringIO.new(input),
      output: output,
      error: error
    )
    [status, output.string, error.string]
  end
end
