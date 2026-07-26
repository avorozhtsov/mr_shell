# frozen_string_literal: true

require "open3"

module MrShell
  class ExternalCommand
    attr_reader :command, :environment

    def initialize(command, environment: { "LC_ALL" => "C" })
      @command = Array(command).map(&:to_s)
      @environment = environment
      raise ConfigurationError, "External command cannot be empty" if @command.empty?
    end

    def call(records, codec)
      Enumerator.new do |output|
        Open3.popen3(environment, *command) do |stdin, stdout, stderr, wait_thread|
          writer = write_records(stdin, records, codec)
          stderr_reader = Thread.new { stderr.read }

          stdout.each_line do |line|
            next if line.strip.empty?

            output << codec.load(line)
          end

          writer_error = thread_error(writer)
          error_text = stderr_reader.value
          status = wait_thread.value

          unless status.success?
            raise ExternalCommandError.new(
              command,
              status: status.exitstatus,
              stderr: error_text
            )
          end
          raise writer_error if writer_error
        end
      rescue SystemCallError => e
        raise ExternalCommandError.new(command, stderr: e.message)
      end
    end

    private

    def write_records(stdin, records, codec)
      thread = Thread.new do
        records.each do |record|
          stdin.write(codec.dump(record))
          stdin.write("\n")
        end
      ensure
        stdin.close unless stdin.closed?
      end
      thread.report_on_exception = false if thread.respond_to?(:report_on_exception=)
      thread
    end

    def thread_error(thread)
      thread.value
      nil
    rescue StandardError => e
      e
    end
  end
end
