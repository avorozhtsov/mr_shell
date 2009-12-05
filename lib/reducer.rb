$:.unshift(File.dirname(__FILE__))

require 'core_ext'
require 'set'
require 'lazy_enumerable'

class Reducer < LazyEnumerable
  attr_accessor :reduce_block
  attr_accessor :map_block
  def sum(rv,v)
    (rv && rv + v) || v
  end

  def join(rv,v)
    (rv||[]) << v
  end

  def uniq(rv,v)
    (rv||Set.new) << v
  end

  def join_map(v)
    "[#{v.to_a.flatten.compact.join(",")}]"
  end
  alias uniq_map join_map

  def min(rv,v)
    (rv && ((rv < v) ? rv : v)) || v
  end

  def max(rv,v)
    (rv && ((rv > v) ? rv : v)) || v
  end

  def prod(rv,v)
    (rv && rv * v) || v
  end

  def avg(rv,v)
    (rv && rv.vsum!([1,v])) || [1,v]
  end
  
  def count(rv, v)
    (rv && rv += 1) || 1
  end

  def avg_map(v)
    v[1].to_f/v[0]
  end

  def freq(rv,v)
    (rv||Hash.new(0))[v] += 1
  end

  def initialize(sig)
    @reduce_block = create_reduce_block(sig) 
    @map_value_block = create_map_block(sig)
    self.reduce!(&@reduce_block) if @reduce_block
    self.map!{|r| [r.key, @map_value_block[r.value]] } if @map_value_block
  end

  OP_RGXP = %r{^[+*]$}
  SIG_RGXP = %r{^([+*\w\d]+)(?:\[([\d,.]+)\])?(\*)?(?:/(.+))?$}
  
  def create_reduce_block(sig)
    if sig.index(";")
      sig.split(";").map{|s| create_reduce_block(s)}.inject(&:+)
    else
      sig,cut,inject = (sig =~ SIG_RGXP  and [$1,$2,$3])
      do_cut = "v = v.cut(#{cut});" if cut
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

  ID_BLOCK = Proc.new{|x| x}
  def create_map_block(sig)
    if sig.index(";")
      blocks = sig.split(";").map{|s| create_map_block(s) || ID_BLOCK}
      return nil if blocks.all?{|b| b == ID_BLOCK}
      blocks.inject(&:&)
    else
      sig,cut,inject,map = (sig =~ SIG_RGXP and [$1,$2,$3,$4])
      return nil unless map || respond_to?("#{sig}_map")
      v = "v"
      if respond_to?("#{sig}_map")
        v = "#{sig}_map(#{v})"
      end
      if map =~ /^\./
        eval "Proc.new{|v| (#{v})#{map}}"
      else
        eval "Proc.new{|v| #{map}(#{v})}"
      end
    end
  end

  def self.add_reduce_method(code)
    @user_method ||= "u0"
    user_method =  (code=~ /^(\w+):/) ? $1 : @user_method.succ!
    code.gsub!(/^(\w+):/, '')
    self.class_eval "
      def #{user_method}(rv,v)
        #{code}
      end
    "
    user_method
  end
end
