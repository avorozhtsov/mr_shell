class Hash
  def except!(*keys_to_delete)
    keys_to_delete.each{|k| self.delete(k)}
    self
  end
end


