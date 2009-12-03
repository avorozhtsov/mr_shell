$:.unshift File.dirname(__FILE__)
require 'core_ext'
require 'lazy_enumerable'
require 'line_record'

#:include: ../README
module Enumerable
  #:call-seq:
  #   enum.reduce {|a,b| ... }          -> new_enum
  #   enum.reduce(output) {|a,b| ... }  -> enum (i.e. self)
  #
  # Reduce records containing in enum. 
  # Generate new_enum in no argument specified.
  # Place reduced records in output (using '<<' operator) if output is specified.
  # Output block (lambda) or stream can be used as argument for this method. 
  def reduce(output_block=nil,&reduce_block)
    output_block ||= []
    last_record = nil
    left_value = nil
    each do |record|
      if last_record && record.key != last_record.key
        output_block << [last_record.key, left_value]
        left_value = nil
      end
      last_record = record
      left_value = reduce_block[left_value, record.value, record]
    end
    output_block << [last_record.key, left_value] 
  end
end

class Array
  #:call-seq:
  #   ary.reduce! {|a,b| ... }                 -> self
  #   ary.reduce!(initial_reduced_value) {|a,b| ... }  -> self 
  #
  # Reduce records in ary. 
  def reduce!(initial_value=nil,&reduce_block)
    j = 0
    reduced_record = self[0]
    (1...size).each do |i|
      record = self[i]
      if record.key != reduced_record.key 
        j += 1
        if initial_value
          reduced_record = record.clone
          reduced_record[1..-1] = initial_value.responds?(:call) ? initial_value.call : initial_value
          self[j] = reduced_record
        else
          reduced_record = record
          self[j] = reduced_record
          next
        end
      else
        reduced_record[1..-1] = reduce_block[reduced_record.value, record.value, record]
      end
    end
    self.slice!(j+1...self.size)
    self
  end
end

LazyEnumerable.class_eval do
  #:call-seq:
  #  lazy_enum.reduce! {|a,b| ... }          -> self
  #
  # Reduce records containing in lazy_enum. 
  # Specified block is block for injecting values of records with same key.
  # See Enumerable#reduce
  def reduce!(&reduce_block)
    @enum = self.clone
    @reduce_block = reduce_block
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.reduce(output_block, &@reduce_block)
      end
    end
    self
  end

  def sort_values_by!(&sort_block)
    @enum = self.reduce!{|rv,v| (rv||[]) << v}.clone
    @sort_block = sort_block
    self.singleton_class.class_eval do
      def each(&output_block)
        @enum.each do |k, values|
          values.sort_by!(&@sort_block).each do |v|
            output_block[ [k,*v] ]
          end
        end
        self
      end
    end
    self
  end
end

def records
  STDIN.to_lazy.select{|line| line =~ /\S/}.map(&:to_record)
end

#:stopdoc:
#
if $0 == __FILE__

  require 'test/unit'

  class TestReduce < Test::Unit::TestCase
    def test_reduce   
      @r1 = [ ['b', 10], ['a', 1], ['a', 3], ['b', 1] ]
      @r1_correct = [['a', 4], ['b', 11]]
      
      @r2 = [ ["d a b c", 10], ["c", 1], ["c d ", 3], ["f a", 100] ]
      @r2_correct = [['a', 110], ['b', 10], ['c', 14], ['d', 13], ['f', 100]] 
    
      assert_equal(
        @r1_correct,
        @r1.sort.reduce{|a,b| (a||=0)+b}
       )
    
      assert_equal(
        @r1_correct,
        @r1.sort.reduce!{|a,b| (a||=0)+b}
       )
       
      assert_equal(
        @r2_correct,
        @r2.sort.
          map{|phrase, frequency| phrase.split.map{|word| [word, frequency]}}.
          inject([]){|new_records, records| new_records.push(*records)}.
          sort.reduce{|a,b| (a||0)+b}
      )

      assert_equal(
        @r2_correct,
        @r2.to_lazy.sort.
          map{|phrase, frequency| phrase.split.map{|word| [word, frequency]}}.
          inject([]){|new_records, records| new_records.push(*records)}.
          sort.reduce{|a,b| (a||0)+b}
      )
    end
  end
end


