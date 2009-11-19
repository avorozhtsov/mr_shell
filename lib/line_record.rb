$:.unshift File.dirname(__FILE__)

require 'core_ext'

module LineRecord

  class <<self
    attr_accessor :field_separator
  
    def field_separator
      @field_separator ||= "\t"
    end
  
    def load_yaml(line)
      if line.index("\t")
        line.gsub!("\t", "\n  - ")
        line.gsub!('\t', "\t")
        YAML.load("---\n" << line)
      else
        line.gsub!(";", "\n")
        line.gsub!('\t', "\t")
        YAML.load("---\n" << line)
      end
    end
    
    def dump_yaml(record)
      if record.is_a?(Array)
        a = record.flatten.to_yaml.strip!
        a.gsub!(/^---\s*/, '')
        a.gsub!("\t", '\t')
        a.gsub!(/(\n|^)- /, "\t")
        a.gsub!("\n", ";")
      else
        a.gsub!(/^---\s*/, '')
        a = record.to_yaml.strip!
        a.gsub!("\t", '\t')
        a.gsub!("\n", ";")
      end
      a
    end

    def load_simple(line)
      v = line.strip!.split(field_separator).map!{|f| 
        case (f.strip!; f)
        when /^[^\d+\-]/
          f
        when /\./
          f.to_f
        when /^\d+$/
          f.to_i
        else
          f
        end
      }
    end
    
    def dump_simple(record)
      record.join(field_separator)
    end
     
    def load_string(line)
      line.strip!.split(field_separator)
    end
    
    def dump_string(record)
      record.join(field_separator)
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
