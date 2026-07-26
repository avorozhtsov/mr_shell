# frozen_string_literal: true

require_relative "test_helper"

class ExternalCommandTest < Minitest::Test
  def test_pipeline_through_external_sort
    records = [
      MrShell::Record.new("b", [2]),
      MrShell::Record.new("a", [1])
    ]
    codec = MrShell::Codecs::JSONLines.new

    result = MrShell::Pipeline.new(records).through(["sort"], codec: codec).to_a

    assert_equal %w[a b], result.map(&:key)
  end

  def test_external_failure_includes_exit_status_and_stderr
    command = [
      RbConfig.ruby,
      "-e",
      'warn "deliberate failure"; exit 7'
    ]
    pipeline = MrShell::Pipeline.new([]).through(
      command,
      codec: MrShell::Codecs::JSONLines.new
    )

    error = assert_raises(MrShell::ExternalCommandError) { pipeline.to_a }
    assert_equal 7, error.status
    assert_match(/deliberate failure/, error.stderr)
  end

  def test_missing_external_command_is_reported
    pipeline = MrShell::Pipeline.new([]).through(
      ["mr-shell-command-that-does-not-exist"],
      codec: MrShell::Codecs::JSONLines.new
    )

    error = assert_raises(MrShell::ExternalCommandError) { pipeline.to_a }
    assert_match(/No such file or directory/, error.message)
  end
end
