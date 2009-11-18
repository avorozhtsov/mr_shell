$:.unshift File.dirname(__FILE__)
require 'core_ext'
require 'line_record'

#
# LazyEnumerable is container postpoining calculation of 
# methods +map+, +select+, +uniq+, +flatten+, .. untill the moment 
# method +each+ is called.
# 
# Lazy enumerables can be used as pipes transforming or filtering data 
# streams.
#
# You can convert any container +enum+ to lazy one by calling +to_lazy+:
#
#  enum.to_lazy
#
# Example:
#
#  cat data.txt | ruby -r lazy_enumerable -e \ 
#    'STDIN.to_lazy.map!(&:to_i).select!{|i| i % 2 == 0 }.each{|i| puts i}'
#
# This piped way of data transformation is useful for data sets bigger than 
# available memory.
#
class LazyEnumerable

  # Creates LazyEnumerable from elements of container +enum+. 
  def initialize(enum)
    @enum = enum
  end
  
  delegate :each, :to => '@enum'
  
  include Enumerable

  def map!(&map_block)
    @enum = self.clone
    @map_block = map_block
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.each do |e| 
          output_block[@map_block[e]]
        end
        self
      end
    end
    self
  end
  
  def map_out!(&map_block)
    @enum = self.clone
    @map_block = map_block
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.each do |e| 
          @map_block[output_block,e]
        end
        self
      end
    end
    self
  end

  def select!(&select_block)
    @enum = self.clone
    @select_block = select_block
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.each do |e| 
          output_block[e] if @select_block[e]
        end
        self
      end
    end
    self
  end
  
  def uniq!
    @enum = self.clone
    @done = {}
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.each do |e| 
          (output_block[e]; @done[e]=true) unless @done[e]
        end
        self
      end
    end
    self
  end
  
  def flatten!
    @enum = self.clone
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.each do |e| 
          [e].flatten.each{|e2| output_block[e2]} 
        end
        self
      end
    end
    self
  end
  
  def sort!(&sort_block)
    @enum = self.clone
    @sort_block = sort_block
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.to_a.sort(&@sort_block).each do |e| 
          output_block[e]
        end
        self
      end
    end
    self
  end
 
  #:call-seq:
  #  lazy_enum.pipe!(cmd)              #=> self
  #  lazy_enum.pipe!(cmd) {|line| ..}  #=> self
  #
  # Returns self with modified elements. Each element is piped through
  # command +cmd+, i.e. elements are converted to lines (method +lo_line)
  # and go to standard input of command +cmd+. Lines in standard output of 
  # this command is converted to elements using String#to_record.
  #
  # Use the second call form if you want to convert lines to records
  # by youself.
  def pipe!(cmd, &map_block)
    @enum = self.clone
    @map_block = map_block 
    @cmd = cmd
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.pipe(@cmd, output_block, &@map_block)
        self
      end
    end
    self
  end
  
  make_nobang :map, :map_out, :select, :flatten, :sort, :pipe
end

Enumerable.module_eval do
  def to_lazy
    LazyEnumerable.new(self)
  end

  #:call-seq:
  #  enum.pipe(cmd)                      #=> self
  #  enum.pipe(cmd) {|line| ..}          #=> self
  #  enum.pipe(cmd, output)              #=> output
  #  enum.pipe(cmd, output) {|line| ..}  #=> output
  #
  # Returns container with modified elements. Each element is piped through
  # command +cmd+, i.e. elements are converted to lines (via method +lo_line)
  # and go to standard input of the command +cmd+. Lines in standard output of 
  # this command are converted to elements using String#to_record.
  #
  # Use form with associated block if you want to convert lines to records
  # by youself.
  #
  # One can specify output container (or Proc object) as second argument.
  def pipe(cmd, output=nil, &map_block)
    output ||= []
    IO.popen(@cmd, 'r+') do |pipe|
      Thread.new {
        @enum.each{|e| pipe.puts(e.to_line)}
        pipe.close_write
      }
      if @map_block
        pipe.each do |line|
          output << @map_block[line]
        end
      else
        pipe.each do |line|
          output << line.to_record
        end
      end
    end
    output
  end
end

# :stopdoc:
if $0 == __FILE__
     
  require 'test/unit'
  class TestLazyEnumerable < Test::Unit::TestCase 
    def test_map  
      assert_equal(
        (0..10).map{|a| a*a}.map!{|a| a-1},
        (0..10).to_lazy.map!{|a| a*a}.map!{|a| a-1}.to_a
      )
    end

    def test_combined
      assert_equal(
        (0..100).map{|a| a*a}.select{|i| i % 2 == 1}.map!{|a| a % 10}.uniq,
        (0..100).to_lazy.map!{|a| a*a}.select!{|i| i % 2 == 1}.map!{|a| a % 10}.uniq!.to_a
      )
    end

    def test_map_with_output
      assert_equal(
        ('a'..'f').to_a,
        ["a b c", "d e", "f"].to_lazy.map_out{|o,p| p.split.each{|w| o << w}}.to_a
      )
    end
  end
end

