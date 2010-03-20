require File.dirname(__FILE__) + '/../helper'
require 'erb'

NormalERB = ::ERB
TempleERB = Temple::Engines::ERB

class TestTempleEnginesERB < Test::Unit::TestCase
  class MyError < RuntimeError ; end
  
  def test_rock_suck
    assert_equal(NormalERB, ::ERB)
    TempleERB.rock!
    assert_equal(TempleERB, ::ERB)
    TempleERB.suck!
    assert_equal(NormalERB, ::ERB)
  end
  
  def test_change_generator
    gen = Temple::Core::StringBuffer
    erb = TempleERB.new("Hello", nil, nil, 'foo', :generator => gen)
    assert_match(/foo = ''/, erb.src)
    
    erb = TempleERB.new("Hello", nil, nil, 'foo', :generator => gen.new(:buffer => "bar"))
    assert_match(/bar = ''/, erb.src)
    assert_no_match(/foo/, erb.src)
  end
  
  def test_optimizers
    obj = Object.new
    def obj.compile(exp)
      [:static, "Hello World!"]
    end
    
    TempleERB::Optimizers << obj
    
    erb = TempleERB.new("Hello")
    assert_equal("Hello World!", erb.result)
  ensure
    TempleERB::Optimizers.delete(obj)
  end

  def test_without_filename
    erb = TempleERB.new("<% raise ::TestTempleEnginesERB::MyError %>")
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\A\(erb\):1\b/, e.backtrace[0])
  end

  def test_with_filename
    erb = TempleERB.new("<% raise ::TestTempleEnginesERB::MyError %>")
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\Atest filename:1\b/, e.backtrace[0])
  end

  def test_without_filename_with_safe_level
    erb = TempleERB.new("<% raise ::TestTempleEnginesERB::MyError %>", 1)
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\A\(erb\):1\b/, e.backtrace[0])
  end

  def test_with_filename_and_safe_level
    erb = TempleERB.new("<% raise ::TestTempleEnginesERB::MyError %>", 1)
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\Atest filename:1\b/, e.backtrace[0])
  end
end

class TestTempleEnginesERBCore < Test::Unit::TestCase
  def setup
    @erb = TempleERB
  end

  def test_core
    _test_core(nil)
    _test_core(0)
    _test_core(1)
    _test_core(2)
    _test_core(3)
  end

  def _test_core(safe)
    erb = @erb.new("hello")
    assert_equal("hello", erb.result)

    erb = @erb.new("hello", safe, 0)
    assert_equal("hello", erb.result)

    erb = @erb.new("hello", safe, 1)
    assert_equal("hello", erb.result)

    erb = @erb.new("hello", safe, 2)
    assert_equal("hello", erb.result)

    src = <<EOS
%% hi
= hello
<% 3.times do |n| %>
% n=0
* <%= n %>
<% end %>
EOS

    ans = <<EOS
%% hi
= hello

% n=0
* 0

% n=0
* 1

% n=0
* 2

EOS
    erb = @erb.new(src)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, 0)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, '')
    assert_equal(ans, erb.result)

    ans = <<EOS
%% hi
= hello
% n=0
* 0% n=0
* 1% n=0
* 2
EOS
    erb = @erb.new(src, safe, 1)
    assert_equal(ans.chomp, erb.result)
    erb = @erb.new(src, safe, '>')
    assert_equal(ans.chomp, erb.result)

    ans  = <<EOS
%% hi
= hello
% n=0
* 0
% n=0
* 1
% n=0
* 2
EOS

    erb = @erb.new(src, safe, 2)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, '<>')
    assert_equal(ans, erb.result)

    ans = <<EOS
% hi
= hello

* 0

* 0

* 0

EOS
    erb = @erb.new(src, safe, '%')
    assert_equal(ans, erb.result)

    ans = <<EOS
% hi
= hello
* 0* 0* 0
EOS
    erb = @erb.new(src, safe, '%>')
    assert_equal(ans.chomp, erb.result)

    ans = <<EOS
% hi
= hello
* 0
* 0
* 0
EOS
    erb = @erb.new(src, safe, '%<>')
    assert_equal(ans, erb.result)
  end

  def test_safe_04
    erb = @erb.new('<%=$SAFE%>', 4)
    assert_equal('4', erb.result(TOPLEVEL_BINDING.taint))
  end

  class Foo; end

  def test_def_class
    erb = @erb.new('hello')
    cls = erb.def_class
    assert_equal(Object, cls.superclass)
    assert(cls.new.respond_to?('result'))
    cls = erb.def_class(Foo)
    assert_equal(Foo, cls.superclass)
    assert(cls.new.respond_to?('result'))
    cls = erb.def_class(Object, 'erb')
    assert_equal(Object, cls.superclass)
    assert(cls.new.respond_to?('erb'))
  end

  def test_percent
    src = <<EOS
%n = 1
<%= n%>
EOS
    assert_equal("1\n", TempleERB.new(src, nil, '%').result)

    src = <<EOS
<%
%>
EOS
    ans = "\n"
    assert_equal(ans, TempleERB.new(src, nil, '%').result)

    src = "<%\n%>"
    # ans = "\n"
    ans = ""
    assert_equal(ans, TempleERB.new(src, nil, '%').result)

    src = <<EOS
<%
n = 1
%><%= n%>
EOS
    assert_equal("1\n", TempleERB.new(src, nil, '%').result)

    src = <<EOS
%n = 1
%% <% n = 2
n.times do |i|%>
%% %%><%%<%= i%><%
end%>
%%%
EOS
    ans = <<EOS
% 
% %%><%0
% %%><%1
%%
EOS
    assert_equal(ans, TempleERB.new(src, nil, '%').result)
  end

  def test_def_erb_method
    klass = Class.new
    klass.module_eval do
      extend ERB::DefMethod
      fname = File.join(File.dirname(File.expand_path(__FILE__)), 'hello.erb')
      def_erb_method('hello', fname)
    end
    assert(klass.new.respond_to?('hello'))

    assert(! klass.new.respond_to?('hello_world'))
    erb = @erb.new('hello, world')
    klass.module_eval do
      def_erb_method('hello_world', erb)
    end
    assert(klass.new.respond_to?('hello_world'))
  end

  def test_def_method_without_filename
    klass = Class.new
    erb = TempleERB.new("<% raise ::TestTempleEnginesERB::MyError %>")
    erb.filename = "test filename"
    assert(! klass.new.respond_to?('my_error'))
    erb.def_method(klass, 'my_error')
    e = assert_raise(::TestTempleEnginesERB::MyError) {
       klass.new.my_error
    }
    assert_match(/\A\(ERB\):1\b/, e.backtrace[0])
  end

  def test_def_method_with_fname
    klass = Class.new
    erb = TempleERB.new("<% raise ::TestTempleEnginesERB::MyError %>")
    erb.filename = "test filename"
    assert(! klass.new.respond_to?('my_error'))
    erb.def_method(klass, 'my_error', 'test fname')
    e = assert_raise(::TestTempleEnginesERB::MyError) {
       klass.new.my_error
    }
    assert_match(/\Atest fname:1\b/, e.backtrace[0])
  end

  def test_escape
    src = <<EOS
1.<%% : <%="<%%"%>
2.%%> : <%="%%>"%>
3.
% x = "foo"
<%=x%>
4.
%% print "foo"
5.
%% <%="foo"%>
6.<%="
% print 'foo'
"%>
7.<%="
%% print 'foo'
"%>
EOS
    ans = <<EOS
1.<% : <%%
2.%%> : %>
3.
foo
4.
% print "foo"
5.
% foo
6.
% print 'foo'

7.
%% print 'foo'

EOS
    assert_equal(ans, TempleERB.new(src, nil, '%').result)
  end

  def test_keep_lineno
    src = <<EOS
Hello, 
% x = "World"
<%= x%>
% raise("lineno")
EOS

    erb = TempleERB.new(src, nil, '%')
    begin
      erb.result
      assert(false)
    rescue
      assert_match(/\A\(erb\):4\b/, $@[0].to_s)
    end

    src = <<EOS
%>
Hello, 
<% x = "World%%>
"%>
<%= x%>
EOS

    ans = <<EOS
%>Hello, 
World%>
EOS
    assert_equal(ans, TempleERB.new(src, nil, '>').result)

    ans = <<EOS
%>
Hello, 

World%>
EOS
    assert_equal(ans, TempleERB.new(src, nil, '<>').result)

    ans = <<EOS
%>
Hello, 

World%>

EOS
    assert_equal(ans, TempleERB.new(src).result)

    src = <<EOS
Hello, 
<% x = "World%%>
"%>
<%= x%>
<% raise("lineno") %>
EOS

    erb = TempleERB.new(src)
    begin
      erb.result
      assert(false)
    rescue
      assert_match(/\A\(erb\):5\b/, $@[0].to_s)
    end

    erb = TempleERB.new(src, nil, '>')
    begin
      erb.result
      assert(false)
    rescue
      assert_match(/\A\(erb\):5\b/, $@[0].to_s)
    end

    erb = TempleERB.new(src, nil, '<>')
    begin
      erb.result
      assert(false)
    rescue
      assert_match(/\A\(erb\):5\b/, $@[0].to_s)
    end

    src = <<EOS
% y = 'Hello'
<%- x = "World%%>
"-%>
<%= x %><%- x = nil -%> 
<% raise("lineno") %>
EOS

    erb = TempleERB.new(src, nil, '-')
    begin
      erb.result
      assert(false)
    rescue
      assert_match(/\A\(erb\):5\b/, $@[0].to_s)
    end

    erb = TempleERB.new(src, nil, '%-')
    begin
      erb.result
      assert(false)
    rescue
      assert_match(/\A\(erb\):5\b/, $@[0].to_s)
    end
  end

  def test_explicit
    src = <<EOS
<% x = %w(hello world) -%>
NotSkip <%- y = x -%> NotSkip
<% x.each do |w| -%>
  <%- up = w.upcase -%>
  * <%= up %>
<% end -%>
 <%- z = nil -%> NotSkip <%- z = x %>
 <%- z.each do |w| -%>
   <%- down = w.downcase -%>
   * <%= down %>
   <%- up = w.upcase -%>
   * <%= up %>
 <%- end -%>
KeepNewLine <%- z = nil -%> 
EOS

   ans = <<EOS
NotSkip  NotSkip
  * HELLO
  * WORLD
 NotSkip 
   * hello
   * HELLO
   * world
   * WORLD
KeepNewLine  
EOS
   assert_equal(ans, TempleERB.new(src, nil, '-').result)
   assert_equal(ans, TempleERB.new(src, nil, '-%').result)
  end

  def test_url_encode
    assert_equal("Programming%20Ruby%3A%20%20The%20Pragmatic%20Programmer%27s%20Guide",
                 ERB::Util.url_encode("Programming Ruby:  The Pragmatic Programmer's Guide"))
    
    if "".respond_to?(:force_encoding)
      assert_equal("%A5%B5%A5%F3%A5%D7%A5%EB",
                  ERB::Util.url_encode("\xA5\xB5\xA5\xF3\xA5\xD7\xA5\xEB".force_encoding("EUC-JP")))
    end
  end
end

class TestTempleEnginesERBCoreWOStrScan < TestTempleEnginesERBCore
  def setup
    @save_map = ERB::Compiler::Scanner.instance_variable_get('@scanner_map')
    map = {[nil, false]=>ERB::Compiler::SimpleScanner}
    ERB::Compiler::Scanner.instance_variable_set('@scanner_map', map)
    super
  end

  def teardown
    ERB::Compiler::Scanner.instance_variable_set('@scanner_map', @save_map)
  end
end
