$:.unshift File.dirname(__FILE__)

require 'core_ext'

module LineRecord

  class <<self
    attr_accessor :field_separator
  
    def field_separator
      @field_separator ||= "\t"
    end
  
    def load_yaml(line)
      line = (field_separartor + line)
      line.gsub!(field_separartor, "- ")
      YAML.load(line) rescue line.split(field_separartor)
    end
    
    def dump_yaml(record)
      a = record.flatten.to_yaml
      a.gsub!(" -", field_separator)
      a
    end
    
    def load_simple(line)
      line.split(field_separator)
    end
    
    def dump_simple(line)
      line.join(field_separator)
    end
    
    alias load load_simple
    alias dump dump_simple
    
  end
end

class Array
  alias :key :first
  def value
    if self.size == 2
      self[1]
    else
      self[1..-1]
    end
  end
  
  def to_line
    LineRecord.dump(self)
  end
  
  def put_record
    puts to_line
  end
end

class String
  def to_record
    LineRecord.load(self)
  end
end

Enumerable.module_eval do
  def put_records
    each{|e| puts e.to_line}
  end
end
