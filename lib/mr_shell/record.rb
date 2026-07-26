# frozen_string_literal: true

module MrShell
  class Record
    attr_reader :key, :values

    def initialize(key, values = [])
      @key = key
      @values = Array(values).dup.freeze
      freeze
    end

    def value
      values.length == 1 ? values.first : values
    end

    def to_a
      [key, *values]
    end

    def ==(other)
      other.is_a?(Record) && key == other.key && values == other.values
    end
    alias eql? ==

    def hash
      [key, values].hash
    end

    def inspect
      "#<#{self.class.name} key=#{key.inspect} values=#{values.inspect}>"
    end
  end
end
