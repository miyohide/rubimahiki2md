# Copyright (c) 2005, Kazuhiko <kazuhiko@fdiary.net>
# Copyright (c) 2007 Minero Aoki
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

require "rubimahiki2md/version"
require "rubimahiki2md/markdown_output"
require "rubimahiki2md/pluginutil"
require "rubimahiki2md/constant"
require "strscan"

module Rubimahiki2md
  class RubimaHiki
    def self.to_md(fname, src, options = {})
      new(MarkdownOutput.new(fname), options).compile(src)
    end

    def initialize(output, options = {})
      @output = output
      @options = options
      @header_re = nil
      @level = options[:level] || 1
      @plugin_syntax = options[:plugin_syntax] || method(:valid_plugin_syntax?)
    end

    def compile(src)
      @output.reset
      escape_plugin_blocks(src) {|escaped|
        compile_blocks escaped
        @output.finish
      }
    end

    private
    def valid_plugin_syntax?(code)
      /['"]/ !~ code.gsub(/\\\\/, "").gsub(/\\['"]/,"").gsub(/'[^']*'|"[^"]*"/m, "")
    end

    def escape_plugin_blocks(text)
      s = StringScanner.new(text)
      buf = ""
      @plugin_blocks = []
      while chunk = s.scan_until(/\{\{/)
        chunk[-2, 2] = ""
        buf << chunk
        if block = extract_plugin_block(s)
          @plugin_blocks.push block
          buf << "\0#{@plugin_blocks.size - 1}\0"
        else
          buf << "{{"
        end
      end
      buf << s.rest
      yield(buf)
    end

    def restore_plugin_block(str)
      str.gsub(/\0(\d+)\0/) {
        "{{" + plugin_block($1.to_i) + "}}"
      }
    end

    def evaluate_plugin_block(str, buf = nil)
      buf ||= @output.container
      str.split(/(\0\d+\0)/).each do |s|
        if s[0, 1] == "\0" and s[-1, 1] == "\0"
          buf << @output.inline_plugin(plugin_block(s[1..-2].to_i))
        else
          buf << @output.text(s)
        end
      end
      buf
    end

    def plugin_block(id)
      @plugin_blocks[id] or raise "must not happen: #{id.inspect}"
    end

    def extract_plugin_block(s)
      pos = s.pos
      buf = ""
      while chunk = s.scan_until(/\}\}/)
        buf << chunk
        buf.chomp!("}}")
        if @plugin_syntax.call(buf)
          return buf
        end
        buf << "}}"
      end
      s.pos = pos
      nil
    end

    def compile_blocks(src)
      f = LineInput.new(StringIO.new(src))
      while line = f.peek
        if f.lineno == 0
          compile_fileheader(f.gets)
          next
        end
        case line
        when COMMENT_REGEX
          f.gets
        when HEADER_REGEX
          compile_header(f.gets)
        when LIST_REGEX
          compile_list(f)
        when DLIST_REGEX
          compile_dlist(f)
        when TABLE_REGEX
          compile_table(f)
        when BLOCKQUOTE_REGEX
          compile_blockquote(f)
        when INDENTED_PRE_REGEX
          compile_indented_pre(f)
        when BLOCK_PRE_OPEN_REGEX
          compile_block_pre(f)
        else
          if /^$/ =~ line
            f.gets
            next
          end
          compile_paragraph(f)
        end
      end
    end

    def compile_fileheader(line)
      @output.fileheader(line)
    end
    ## // からはじまるものはコメント
    COMMENT_REGEX = /\A\/\//
    def skip_comments(f)
      f.while_match(COMMENT_REGEX) do |line|
      end
    end
    ## !ではじまっているものはヘッダー
    HEADER_REGEX = /\A!+/
    def compile_header(line)
      @header_re ||= /\A!{1,#{7 - @level}}/
      level = @level + (line.slice!(@header_re).size - 1)
      title = strip(line)
      @output.headline(level, compile_inline(title))
    end
    # 数字リスト、非数字リスト
    ULIST = "*"
    OLIST = "#"
    LIST_REGEX = /\A#{Regexp.union(ULIST, OLIST)}+/
    def compile_list(f)
      @output.list_start
      f.while_match(LIST_REGEX) do |line|
        list_type = (line[0,1] == ULIST ? "*" : "1.")
        level = line.slice(LIST_REGEX).size
        item = strip(line.sub(LIST_REGEX, ""))
        @output.listitem(list_type, compile_inline(item), level)
      end
      @output.list_end
    end
    ## 定義リスト
    ## 「:項目:定義」という形式。
    DLIST_REGEX = /\A:/
    def compile_dlist(f)
      f.while_match(DLIST_REGEX) do |line|
        dt, dd = split_dlitem(line.sub(DLIST_REGEX, ""))
        @output.dlist_item(compile_inline(dt), compile_inline(dd))
        skip_comments(f)
      end
    end
    ## :で2つに区切る
    def split_dlitem(line)
      ## NOTE リンクのように[[]]の形は:が含まれるのでそれを考慮する
      re = /\A((?:#{BRACKET_LINK_REGEX}|.)*?):/o
      if m = re.match(line)
        return m[1], m.post_match
      else
        return line, ""
      end
    end
    ## テーブル
    TABLE_REGEX = /\A\|\|/
    def compile_table(f)
      lines = []
      f.while_match(TABLE_REGEX) do |line|
        lines.push(line)
        skip_comments(f)
      end
      have_header = false
      columns_num = 0
      @output.table_open
      lines.each do |line|
        @output.table_record_open
        columns = split_columns(line.sub(TABLE_REGEX, ""))
        columns_num = columns.size
        columns.each do |col|
          col.chomp!
          # カラムの頭に!があればテーブルヘッダーとして取り扱う
          have_header = true if col.sub!(/\A!/, '')
          span = col.slice!(/\A[\^>]*/)
          rs = span_count(span, "^")
          cs = span_count(span, ">")
          @output.table_data(compile_inline(col), rs, cs)
          # @output.__send__(mid, compile_inline(col), rs, cs)
        end
        @output.table_record_close
        if have_header
          @output.table_head_line(columns_num)
          have_header = false
        end
      end
      @output.table_close
    end

    def split_columns(str)
      cols = str.split(/\|\|/)
      cols.pop if cols.last.chomp.empty?
      cols
    end

    def span_count(str, ch)
      c = str.count(ch)
      c == 0 ? nil : c + 1
    end

    ## 引用
    BLOCKQUOTE_REGEX = /\A""[ \t]?/
    def compile_blockquote(f)
      @output.blockquote_open
      f.while_match(BLOCKQUOTE_REGEX) do |line|
        @output.blockquote_line(evaluate_plugin_block(line.sub(BLOCKQUOTE_REGEX, "")))
        skip_comments(f)
      end
      @output.blockquote_close
    end

    ## 先頭にスペースが有る場合は整形済み
    INDENTED_PRE_REGEX = /\A[ \t]/
    def compile_indented_pre(f)
      lines = f.span(INDENTED_PRE_REGEX)\
        .map {|line| rstrip(line.sub(INDENTED_PRE_REGEX, "")) }
      text = restore_plugin_block(lines.join("\n"))
      @output.preformatted(text)
    end

    ## <<<型 〜 >>>のものはコードブロック。型は有ってもなくても。
    BLOCK_PRE_OPEN_REGEX = /\A<<<\s*(\w+)?/
    BLOCK_PRE_CLOSE_REGEX = /\A>>>/
    def compile_block_pre(f)
      m = BLOCK_PRE_OPEN_REGEX.match(f.gets) or raise "must not happen"
      str = restore_plugin_block(f.break(BLOCK_PRE_CLOSE_REGEX).join.chomp)
      f.gets
      @output.block_preformatted(str, m[1])
    end

    BLANK = /\A$/
    PARAGRAPH_END_REGEX =
      Regexp.union(BLANK,
                  HEADER_REGEX, LIST_REGEX, DLIST_REGEX,
                  BLOCKQUOTE_REGEX, TABLE_REGEX,
                  INDENTED_PRE_REGEX, BLOCK_PRE_OPEN_REGEX)

    def compile_paragraph(f)
      lines = f.break(PARAGRAPH_END_REGEX)\
        .reject {|line| COMMENT_REGEX =~ line }
      if lines.size == 1 and /\A\0(\d+)\0\z/ =~ strip(lines[0])
        @output.block_plugin plugin_block($1.to_i)
      else
        line_buffer = @output.container(:paragraph)
        lines.each_with_index do |line, i|
          buffer = @output.container
          line_buffer << buffer
          compile_inline(lstrip(line).chomp, buffer)
        end
        @output.paragraph(line_buffer)
      end
    end

    #
    # Inline Level
    #

    BRACKET_LINK_REGEX = /\[\[.+?\]\]/
    URI_REGEX = /(?:https?|ftp|file|mailto):[A-Za-z0-9;\/?:@&=+$,\-_.!~*\'()#%]+/
    def inline_syntax_re
      / (#{BRACKET_LINK_REGEX})
      | (#{URI_REGEX})
      | (#{MODIFIER_REGEX})
      /xo
    end

    def compile_inline(str, buf = nil)
      buf ||= @output.container
      re = inline_syntax_re
      pending_str = nil
      while m = re.match(str)
        str = m.post_match

        link, uri, mod = m[1, 3]

        pre_str = "#{pending_str}#{m.pre_match}"
        pending_str = nil
        evaluate_plugin_block(pre_str, buf)
        compile_inline_markup(buf, link, uri, mod)
      end
      evaluate_plugin_block(pending_str || str, buf)
      buf
    end

    def compile_inline_markup(buf, link, uri, mod)
      case
      when link
        buf << compile_bracket_link(link[2...-2])
      when uri
        buf << compile_uri_autolink(uri)
      when mod
        buf << compile_modifier(mod)
      else
        raise "must not happen"
      end
    end

    def compile_bracket_link(link)
      if m = /\A(.*)\|/.match(link)
        title = m[0].chop
        uri = m.post_match
        fixed_uri = fix_uri(uri)
        if can_image_link?(uri)
          @output.image_hyperlink(fixed_uri, title)
        else
          @output.hyperlink(fixed_uri, compile_modifier(title))
        end
      else
        fixed_link = fix_uri(link)
        if can_image_link?(link)
          @output.image_hyperlink(fixed_link)
        else
          @output.hyperlink(fixed_link, @output.text(link))
        end
      end
    end

    def can_image_link?(uri)
      image?(uri)
    end

    def compile_uri_autolink(uri)
      if image?(uri)
        @output.image_hyperlink(fix_uri(uri))
      else
        @output.hyperlink(fix_uri(uri), @output.text(uri))
      end
    end

    def fix_uri(uri)
      if /\A(?:https?|ftp|file):(?!\/\/)/ =~ uri
        uri.sub(/\A\w+:/, "")
      else
        uri
      end
    end

    IMAGE_EXTS = %w(.jpg .jpeg .gif .png)

    def image?(uri)
      IMAGE_EXTS.include?(uri[/\.[^.]+\z/].to_s.downcase)
    end

    STRONG = "'''"   ## 強調。HTMLでいうstrong
    EM = "''"        ## 強調。HTMLでいうem
    DEL = "=="       ## 削除
    TT = "``"        ## 等幅フォントで表示。HTMLでいうtt。

    STRONG_REGEX = /'''.+?'''/
    EM_REGEX     = /''.+?''/
    DEL_REGEX    = /==.+?==/
    TT_REGEX    = /``.+?``/

    MODIFIER_REGEX = Regexp.union(STRONG_REGEX, EM_REGEX, DEL_REGEX, TT_REGEX)

    MODTAG = {
      STRONG => "strong",
      EM     => "em",
      DEL    => "del",
      TT     => 'tt'
    }

    def compile_modifier(str)
      buf = @output.container
      while m = / (#{MODIFIER_REGEX})
        /xo.match(str)
        evaluate_plugin_block(m.pre_match, buf)
        case
        when chunk = m[1]
          mod, s = split_mod(chunk)
          mid = MODTAG[mod]
          buf << @output.__send__(mid, compile_inline(s))
        else
          raise "must not happen"
        end
        str = m.post_match
      end
      evaluate_plugin_block(str, buf)
      buf
    end

    def split_mod(str)
      case str
      when /\A'''/
        return str[0, 3], str[3...-3]
      when /\A''/
        return str[0, 2], str[2...-2]
      when /\A==/
        return str[0, 2], str[2...-2]
      when /\A``/
        return str[0, 2], str[2...-2]
      else
        raise "must not happen: #{str.inspect}"
      end
    end

    def strip(str)
      rstrip(lstrip(str))
    end

    def rstrip(str)
      str.sub(/[ \t\r\n\v\f]+\z/, "")
    end

    def lstrip(str)
      str.sub(/\A[ \t\r\n\v\f]+/, "")
    end

    class LineInput
      def initialize(f)
        @input = f
        @buf = []
        @lineno = 0
        @eof_p = false
      end

      def inspect
        "\#<#{self.class} file=#{@input.inspect} line=#{lineno()}>"
      end

      def eof?
        @eof_p
      end

      def lineno
        @lineno
      end

      def gets
        unless @buf.empty?
          @lineno += 1
          return @buf.pop
        end
        return nil if @eof_p   # to avoid ARGF blocking.
        line = @input.gets
        line = line.sub(/\r\n/, "\n") if line
        @eof_p = line.nil?
        @lineno += 1
        line
      end

      def ungets(line)
        return unless line
        @lineno -= 1
        @buf.push line
        line
      end

      def peek
        line = gets()
        ungets line if line
        line
      end

      def next?
        peek() ? true : false
      end

      def skip_blank_lines
        n = 0
        while line = gets()
          unless line.strip.empty?
            ungets line
            return n
          end
          n += 1
        end
        n
      end

      def gets_if(re)
        line = gets()
        if not line or not (re =~ line)
          ungets line
          return nil
        end
        line
      end

      def gets_unless(re)
        line = gets()
        if not line or re =~ line
          ungets line
          return nil
        end
        line
      end

      def each
        while line = gets()
          yield line
        end
      end

      def while_match(re)
        while line = gets()
          unless re =~ line
            ungets line
            return
          end
          yield line
        end
        nil
      end

      def getlines_while(re)
        buf = []
        while_match(re) do |line|
          buf.push line
        end
        buf
      end

      alias span getlines_while   # from Haskell

      def until_match(re)
        while line = gets()
          if re =~ line
            ungets line
            return
          end
          yield line
        end
        nil
      end

      def getlines_until(re)
        buf = []
        until_match(re) do |line|
          buf.push line
        end
        buf
      end

      alias break getlines_until   # from Haskell

      def until_terminator(re)
        while line = gets()
          return if re =~ line   # discard terminal line
          yield line
        end
        nil
      end

      def getblock(term_re)
        buf = []
        until_terminator(term_re) do |line|
          buf.push line
        end
        buf
      end
    end
  end
end
