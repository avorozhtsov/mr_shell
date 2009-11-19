class Proc
  alias << call

  class MultipleValue < Array
    def initialize(*args)
      args.each_with_index{|e,i| self[i] = e}
    end
    def each_with_recursion(&block)
      each_without_recursion do |e|
        if e.is_a?(MultipleValue)
          e.each(&block)
        else
          block[e]
        end
      end
    end
    alias each_without_recursion each
    alias each each_with_recursion
  end
 
  attr_accessor :together_blocks
  # protected :together_blocks, :together_blocks=

  def together(other)
    block = Proc.new do |reduced_value, e|
      reduced_value = MV( *([reduced_value]*block.together_blocks.size) ) unless reduced_value.is_a?(MultipleValue)
      i = -1
      reduced_value.map!{|rv|
        block.together_blocks[i+=1][rv, e] 
      } 
    end
    block.together_blocks = (self.together_blocks || [self]) + (other.together_blocks || [other])
    block
  end
  alias + together 
end

def MV(*args)
  Proc::MultipleValue.new(*args)
end

class Symbol
  unless public_method_defined? :to_proc
    def to_proc
      Proc.new { |*args| args.shift.__send__(self, *args) }
    end
  end
end

if $0 == __FILE__
  require 'test/unit'
  class TestProcExt < Test::Unit::TestCase
    def test_reducers_sum
    
      b = :+.to_proc + :*.to_proc

      assert_equal(
        [15, 120],
        [1,2,3,4,5].inject(&b)
      )

      assert_equal(
        [17, 240],
        [1,2,3,4,5].inject(2, &b)
      )

      assert_equal(
        [17, 1200],
        [1,2,3,4,5].inject( MV(2,10),  &b )
      )
      
      c = :+.to_proc + :+.to_proc + :+.to_proc
      assert_equal(
        [15, 16, 17],
        [1,2,3,4,5].inject( MV(0,1,2),  &c ).to_a
      )
    end

    def test_abc
      a = :+.to_proc
      b = a + :*.to_proc
      d = lambda{|x,y| [x,y].min}
      c = b + d
      e = d + b
      assert_equal(
        6,  
        [1,2,3].inject(&a)
      )

      assert_equal(
        1,  
        [4,3,1,4,5].inject(&d)
      )
    
      assert_equal(
        [10, 30],
        [2,3,5].inject(&b)
      )
      
      assert(
        3,
        c.send(:together_blocks).size
      )

      assert_equal(
        [10, 30, 2],
        [3,2,5].inject(&c)
      )

      assert_equal(
        [2, 10, 30],
        [3,2,5].inject(&e)
      )
    end
  end
end

