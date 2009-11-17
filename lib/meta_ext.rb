$:.unshift File.dirname(__FILE__)

class Object
  def singleton_class
    (class<<self; self; end) rescue nil
  end
end

def extract_options(args)
  if args.last.is_a?(Hash)
    args.pop
  else
    {}
  end
end

class Proc
  # This alias make it possible use blocks as virtual input streams or arrays. 
  alias :<< :call
end

class Symbol
  unless public_method_defined? :to_proc
    def to_proc
      Proc.new { |*args| args.shift.__send__(self, *args) }
    end
  end
end

class Module
  def require_and_include(module_undescored)
    begin
      require module_undescored rescue nil
      include module_undescored.camelize
    rescue Exception=>e
      # TODO
      # skip undefined constant exception  
    end
  end
  
  def alias_method(a,b)
    module_eval "alias #{a} #{b}" if a.to_sym != b.to_sym
  end
  
  def alias_method_chain(method, feature)
    alias_method "#{method}_without_#{feature}", "#{method}"
    alias_method "#{method}", "#{method}_with_#{feature}"
  end
  
  # :call-seq:
  #   delegate m1, m2, ..., :to => attr
  #
  # Defines methods +m1+, +m2+, ... as delegated to +attr+
  # Use it in class/module context.
  def delegate(*methods)
    options = extract_options(methods)
    methods.each do |method|
      class_eval "def #{method}(*args,&block); #{options[:to]}.#{method}(*args,&block); end"
    end
  end
  
  def make_nobang(*methods)
    methods.each do |method|
      method = method.to_s.gsub(/!$/, '')
      class_eval "def #{method}(*a,&b); self.clone.#{method}!(*a,&b); end"
    end
  end
  
  public :include
end



