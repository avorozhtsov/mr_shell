require 'core_ext'

def cut(ary,*args)
  result = args.inject([]){|result, range| 
    case range  
    when Range
      result.push(*ary[range])
    else
      result.push(ary[range])
    end
  }
  result.size == 1 ?  result.first : result
end

class Reducer 
  attr_accessor :reduce_block
  def reduce(rv,v)
    reduce_block[rv,v]
  end

  def sum(rv,v)
    (rv||0) + v
  end

  def min(rv,v)
    rv.nil? ? v : ((rv < v) ? rv : v)
  end

  def mul(rv,v)
    (rv||1) * v
  end

  def freq(rv,v)
    (rv||Hash.new(0))[v] += 1
  end

  def initialize(sig)
    @reduce_block = create_reduce_block(sig) 
  end

  OP_RGXP = %r{^[+*\-&|%/]$}
 
  def create_reduce_block(sig)
    if sig.index(";")
      sig.split(";").map{|s| create_reduce_block(s)}.inject(&:+)
    else
      sig,cut,inject = (sig =~ /^([+*&|\w\d]+)(?:\[([\d,.]+)\])?(\*)?$/ and [$1,$2,$3])
      do_cut = "v=cut(v, #{cut});" if cut
      if inject
        if sig =~ OP_RGXP
          eval "Proc.new{|rv,v| #{do_cut} [v].flatten.inject(rv){|rv1,v1| (rv1 #{sig} v1)}}"
        else
          eval "Proc.new{|rv,v| #{do_cut} [v].flatten.inject(rv){|rv1,v1| #{sig}(rv1,v1)}}"
#{sig}(rv,v)}"
        end
      else
        if sig =~ OP_RGXP
          eval "Proc.new{|rv,v| #{do_cut} (rv #{sig} v)}"
        else
          eval "Proc.new{|rv,v| #{do_cut} #{sig}(rv,v)}"
        end
      end
    end
  end

  def self.add_reduce_method(code)
    @user_method ||= "u000"
    user_method =  (code=~ /^(\w+:)/) ? $1 : @user_method.succ!
    self.class_eval "
      def #{user_method}(rv,v)
        #{code}
      end 
    "
    user_method
  end
end
