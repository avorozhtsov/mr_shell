# frozen_string_literal: true

module MrShell
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class DataError < Error; end
  class EvaluationError < DataError; end
  class ContractError < Error; end

  class StageError < DataError
    attr_reader :stage, :original

    def initialize(stage, original)
      @stage = stage
      @original = original
      super("#{stage} failed: #{original.message}")
      set_backtrace(original.backtrace)
    end
  end

  class ExternalCommandError < Error
    attr_reader :command, :status, :stderr

    def initialize(command, status: nil, stderr: "")
      @command = command
      @status = status
      @stderr = stderr

      detail = status ? " (exit #{status})" : ""
      detail += ": #{stderr.strip}" unless stderr.strip.empty?
      super("External command failed#{detail}: #{command.join(' ')}")
    end
  end
end
