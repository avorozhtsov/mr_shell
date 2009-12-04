class Array
  def vsum!(ary)
    (0...self.size).each do |idx|
      self[idx] += ary[idx]
    end
    self
  end

  def uminus!(ary)
    (0...self.size).each do |idx|
      self[idx] = -self[idx]
    end
    self
  end

  def sort_by!(&block)
    sort!{|a,b| block[a] <=> block[b]}
  end

  def second
    self[1]
  end
  
  def to_s
    '[' + join(", ") + ']'
  end

  def cut(*args)
    result = args.inject([]){|result, range|
      case range
      when Range
        result.push(*self[range])
      else
        result.push(self[range])
      end
    }
    result.size == 1 ?  result.first : result
  end
end
