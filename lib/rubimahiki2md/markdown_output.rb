# Copyright (c) 2017 Hidenori Miyoshi
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
#     * Neither the name of the HikiDoc nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
require 'stringio'
require 'uri'

module Rubimahiki2md
  class MarkdownOutput
    ARG_RE = /['"](.+?)['"]/

    def initialize(fname)
      @f = nil
      @footnote_count = 0
      @footnote_list = nil
      @filename = fname
    end

    def reset
      @f = StringIO.new
      @footnote_list = []
    end

    def finish
      footnote_flush
      @f.string
    end

    def footnote_flush
      @f.puts
      @f.puts @footnote_list.join("\n")
    end

    def container(_for=nil)
      case _for
      when :paragraph
        []
      else
        ""
      end
    end

    def fileheader(str)
      @f.puts '---'
      @f.puts 'layout: post'
      @f.puts "title: #{str.tr(':', '：').gsub(/\"/, '\"')}"
      @f.puts "#{short_title(str)}"
      @f.puts "tags: #{jekyll_tag}"
      @f.puts '---'
      @f.puts
    end

    def headline(level, title)
      @f.puts
      @f.puts '#' * (level+1) + " #{title}"
    end

    def list_start
      @f.puts
    end

    def listitem(type, item, level)
      @f.puts ' ' * (2 * level - 2) + "#{type} #{item}"
    end

    def list_end
      @f.puts
    end

    def dlist_item(dt, dd)
      case
      when dd.empty?
        @f.puts
        @f.puts dt
      when dt.empty?
        @f.puts ": #{dd}"
      else
        @f.puts
        @f.puts dt
        @f.puts ": #{dd}"
      end
    end

    def table_open
      @f.puts
    end

    def table_close
      @f.puts
    end

    def table_record_open
      @f.print
    end

    def table_record_close
      @f.puts '|'
    end

    def table_head(item, rs, cs)
      @f.print "<th#{tdattr(rs, cs)}>#{item}</th>"
    end

    def table_head_line(num)
      @f.print "|---" * num + "|\n"
    end

    def table_data(item, rs, cs)
      @f.print "| #{item}"
    end

    def tdattr(rs, cs)
      buf = ""
      buf << %Q( rowspan="#{rs}") if rs
      buf << %Q( colspan="#{cs}") if cs
      buf
    end
    private :tdattr

    def blockquote_open
      @f.puts
    end

    def blockquote_line(str)
      @f.puts "> #{escape_markdown(str)}"
    end

    def blockquote_close
      @f.puts
    end

    def block_preformatted(str, info)
      syntax = info.nil? ? 'text' : info.downcase
      @f.puts
      @f.puts "{% highlight #{syntax} %}"
      @f.puts "{% raw %}"
      @f.puts str
      @f.puts "{% endraw %}"
      @f.puts "{% endhighlight %}"
      @f.puts
    end

    def preformatted(str)
      @f.puts
      @f.puts "{% highlight text %}"
      @f.puts "{% raw %}"
      @f.puts str
      @f.puts "{% endraw %}"
      @f.puts "{% endhighlight %}"
      @f.puts
    end

    def paragraph(lines)
      # paragraphを示すために、始まる前に改行を入れる。
      # 終わりにも入れないのは、paragraphが連続したときに
      # 改行が続くのを避けるため。
      @f.puts
      @f.puts "#{lines.join("\n")}"
    end

    def block_plugin(str)
      method, *args = Hiki::Util.methodwords(str)
      begin
        @f.puts send(method, *args)
      rescue NoMethodError
        @f.puts %Q(<div class="block_plugin">{{#{escape_html(str)}}}</div>)
      rescue NameError
        STDERR.puts "Raise NameError. filename = #{@filename} str = #{str}"
        @f.puts %Q(<div class="plugin block_plugin">{{#{escape_html(str)}}}</div>)
      end
    end

    def hyperlink(uri, title)
      case uri
      when /\Aruby\-list:(\d+)/
        "[#{title}](http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-list/#{$1})"
      when /\Aruby\-dev:(\d+)/
        "[#{title}](http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-dev/#{$1})"
      when /\Aruby\-talk:(\d+)/
        "[#{title}](http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/#{$1})"
      when /\Aruby\-core:(\d+)/
        "[#{title}](http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-core/#{$1})"
      when /\ARAA:(.+)/
        "[#{title}](http://raa.ruby-lang.org/project/#{$1})"
      when /\ARWiki:(.+)/
        "[#{title}](http://pub.cozmixng.org/~the-rwiki/rw-cgi.rb?cmd=view;name=#{URI.encode_www_form_component($1.encode("EUC-JP"))})"
      when /\AFirstStepRuby\Z/
        "[#{title}](https://github.com/rubima/rubima/blob/master/first_step_ruby/first-step-ruby-2.0.md)"
      when /\A(\d{4})\-bbs\Z/
        " ~~#{title}~~ "
      when /\A(\d{4})\-(.+)\Z/
        article_file = "articles/#{$1}/#{ISSUE_DATE[$1]}-#{$1}-#{$2.sub(/#.+\Z/, '')}"
        if title == uri
          uri = uri.sub(/#.+\Z/, '')
          "[#{TITLES[uri]}]({% post_url #{article_file} %})"
        else
          "[#{title}]({% post_url #{article_file} %})"
        end
      else
        "[#{title}](#{uri})"
      end
    end

    def image_hyperlink(uri, alt = nil)
      alt ||= uri.split(/\//).last
      alt = escape_html(alt)
      "![#{alt}](#{escape_html_param(uri)})"
    end

    def strong(item)
      "__#{item}__"
    end

    def em(item)
      "_#{item}_"
    end

    def del(item)
      " ~~#{item}~~ "
    end

    def tt(item)
      "`#{item}`"
    end

    def text(str)
      escape_html(str)
    end

    def inline_plugin(src)
      method, *args = Hiki::Util.methodwords(src)
      begin
        send(method, *args)
      rescue NoMethodError
        %Q(<div class="plugin inline_plugin">{{#{escape_html(src)}}}</div>)
      rescue NameError
        STDERR.puts "Raise NameError. filename = #{@filename} src = #{src}"
        %Q(<div class="plugin inline_plugin">{{#{escape_html(src)}}}</div>)
      end
    end

    def backnumber(*args)
      "\n{% for post in site.tags.#{args[0]} %}\n  - [{{ post.title }}]({{ post.url }})\n{% endfor %}\n"
    end

    def attach_rb(*args)
      attach_source('ruby', args[0])
    end

    def attach_src(*args)
      attach_source('', args[0])
    end

    alias :attach_pre :attach_src

    def attach_html(*args)
      attach_source('html', args[0])
    end

    def attach_source(type, fname)
      f = File.open("attach/#{attach_dir_name}/#{fname}").read
      "\n```#{type}\n#{escape_jekyll_tag(f)}\n```\n"
    end

    def toc_here(*args)
      "\n* Table of content\n{:toc}\n\n"
    end

    alias :toc :toc_here

    def fn(*args)
      footnote_text = args[0].gsub(/&quot;/, '"')
      footnote_text.gsub!(/\[\[([^|]+?)\|(.+?)\]\]/) { hyperlink($2, $1) }
      footnote_text.gsub!(/{{.+?}}/) { |matched| inline_plugin(matched[2...-2]) }
      @footnote_count += 1
      @footnote_list << "[^#{@footnote_count}]: #{footnote_text}"
      "[^#{@footnote_count}]"
    end

    def sub(*args)
      "<sub>#{args[0]}</sub>"
    end

    # コメント欄は廃止したため、空を返す
    def comment
      ''
    end

    # トラックバックは廃止したため、空を返す
    def trackback
      ''
    end

    def speakerdeck(*args)
      "\n[#{args[0]}](#{args[1]})"
    end

    def isbn(*args)
      "{% isbn('#{args[0]}', '#{args[1]}') %}"
    end

    def attach_view(*args)
      if args[0] == 'u26.gif'
        "![title_mark.gif]({{site.baseurl}}/images/title_mark.gif)"
      else
        "![#{args[0]}](#{attach_path(args[0])})"
      end
    end

    alias :attach_image_anchor :attach_view

    def attach_expandimg(*args)
      "![#{args[0]}](#{attach_path(args[0])})"
    end

    def br
      '<br />'
    end

    def attach_anchor(*args)
      "[#{args[0]}](#{attach_path(args[0])})"
    end

    def attach_anchor_string(*args)
      "[#{args[0]}](#{attach_path(args[1])})"
    end

    def e(*args)
      "&##{args[0]};"
    end

    def isbn_image_right(*args)
      "{% isbn_image_right('#{args[0]}') %}"
    end

    alias :isbnImgRight :isbn_image_right

    def isbn_image_left(*args)
      "{% isbn_image_left('#{args[0]}') %}"
    end

    alias :isbnImgLeft :isbn_image_left

    def isbn_image(*args)
      label = args[1] || ''
      "{% isbn_image('#{args[0]}', '#{label}') %}"
    end

    alias :isbnImg :isbn_image
    alias :amazon :isbn_image

    def youtube(*args)
      %Q!<object width="560" height="315"><param name="movie" value="http://www.youtube.com/v/#{args[0]}"></param><embed src="http://www.youtube.com/v/#{args[0]}" type="application/x-shockwave-flash" width="560" height="315"></embed></object>!
    end

    def ansi_screen(*args)
      rval = %Q!<pre class="screen" style="color: white; background-color: black; padding: 0.5em; width: 40.0em">\n!
      contents = File.read("attach/#{attach_dir_name}/#{args[0]}")
      contents.gsub!(/\e\[32m(.+?)\e\[0m/m) { "<span style='color: lime'>#{$1}</span>\n" }
      contents.gsub!(/\e\[31m(.+?)\e\[0m/m) { "<span style='color: red'>#{$1}</span>\n" }
      rval << contents
      rval << "</pre>"
      rval
    end

    #
    # Utilities
    #

    def escape_html_param(str)
      escape_quote(escape_html(str))
    end

    def escape_html(text)
      text.gsub(/&/, "&amp;").gsub(/</, "&lt;").gsub(/>/, "&gt;")
    end

    def escape_jekyll_tag(text)
      text.gsub(/{{/, '\{\{').gsub(/}}/, '\}\}')
    end

    def unescape_html(text)
      text.gsub(/&gt;/, ">").gsub(/&lt;/, "<").gsub(/&amp;/, "&")
    end

    def escape_quote(text)
      text.gsub(/"/, "&quot;")
    end

    def escape_markdown(text)
      text.sub(/^(\s*)#/) { "#{$1}\\#" }
    end

    def method_args(name, str)
      if m = str.match(/#{name}\s*\(?#{ARG_RE}(?:\s*,\s*#{ARG_RE})*\)/)
        [m[1], m[2]]
      else
        []
      end
    end

    def attach_path(name)
      "{{site.baseurl}}/images/#{attach_dir_name}/#{name}"
    end

    def attach_dir_name
      File.basename(@filename, '.hiki')
    end

    def issue_num
      attach_dir_name.split('-')[0]
    end

    def article_tag
      attach_dir_name.split('-')[1]
    end

    def short_title(str)
      if index?
        "short_title: #{issue_num}号(#{short_date})"
      else
        "short_title: #{str.tr(':', '：').gsub(/\"/, '\"')}"
      end
    end

    def short_date
      t = ISSUE_DATE[issue_num].split('-')
      "#{t[0]}-#{t[1]}"
    end

    def jekyll_tag
      if index?
        "#{issue_num} index"
      else
        "#{issue_num} #{article_tag}"
      end
    end

    def index?
      if attach_dir_name =~ /\A\d{4}\Z/
        true
      else
        false
      end
    end
  end
end
