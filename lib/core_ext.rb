$:.unshift File.dirname(__FILE__)

require 'meta_ext'
require 'proc_ext'
require 'hash_ext'
require 'array_ext'

class Object
  def to_line
    to_s + "\n"
  end 
end
