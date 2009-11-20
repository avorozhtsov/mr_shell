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
  
end
