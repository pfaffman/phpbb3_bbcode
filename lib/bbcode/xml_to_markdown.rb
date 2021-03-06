require 'nokogiri'

module BBCode
  class XmlToMarkdown
    def initialize(xml, opts = {})
      @reader = Nokogiri::XML::Reader(xml) do |config|
        config.noblanks
      end

      @username_from_user_id = opts[:username_from_user_id]
      @smilie_to_emoji = opts[:smilie_to_emoji]
      @quoted_post_from_post_id = opts[:quoted_post_from_post_id]
    end

    def convert
      @list_stack = []
      @element_stack = []
      @ignore_node_count = 0
      @consecutive_br_count = 0
      @markdown = ""

      @reader.each { |node| visit(node) }
      @markdown.rstrip
    end

    protected

    def visit(node)
      visitor = "visit_#{node.name.gsub(/\W/, '_')}"
      is_start_element = start?(node)

      calc_consecutive_br_count(node)
      @element_stack.pop if !is_start_element && @element_stack.last == node.name

      send(visitor, node) if respond_to?(visitor, include_all: true)
      @element_stack << node.name if is_start_element
    end

    def visit__text(node)
      return if @ignore_node_count > 0

      if @within_code_block
        @code << text(node, escape_markdown: false)
      else
        @markdown << text(node).lstrip.sub(/\n\s*\z/, '')
      end
    end

    def visit_B(node)
      @markdown << '**'
    end

    def visit_I(node)
      @markdown << '_'
    end

    def visit_U(node)
      @markdown << (start?(node) ? '[u]' : '[/u]')
    end

    def visit_CODE(node)
      if start?(node)
        @within_code_block = true
        @code = ''
      else
        if @code.include?("\n")
          @code.sub!(/\A[\n\r]*/, '')
          @code.rstrip!
          @markdown = "```text\n#{@code}\n```"
        else
          @markdown = "`#{@code}`"
        end

        @within_code_block = false
        @code = nil
      end
    end

    def visit_LIST(node)
      if start?(node)
        add_new_line_around_list

        @list_stack << {
            unordered: node.attribute('type').nil?,
            item_count: 0
        }
      else
        @list_stack.pop
        add_new_line_around_list
      end
    end

    def add_new_line_around_list
      return if @markdown.empty?
      ends_with_new_line = @markdown.end_with?("\n")

      if ends_with_new_line ^ (@list_stack.size > 0)
        @markdown << "\n"
      elsif !ends_with_new_line
        @markdown << "\n\n"
      end
    end

    def visit_LI(node)
      if start?(node)
        list = @list_stack.last
        depth = @list_stack.size - 1

        list[:item_count] += 1

        indentation = ' ' * 2 * depth
        symbol = list[:unordered] ? '*' : "#{list[:item_count]}."

        @markdown << "#{indentation}#{symbol} "
      else
        @markdown << "\n" unless @markdown.end_with?("\n")
      end
    end

    def visit_IMG(node)
      ignore_node(node)
      @markdown << "![](#{node.attribute('src')})" if start?(node)
    end

    def visit_URL(node)
      return if @element_stack.last == 'IMG'

      if start?(node)
        @markdown_before_link = @markdown
        @markdown = ''
      else
        url = node.attribute('url')
        link_text = @markdown
        @markdown = @markdown_before_link
        @markdown_before_link = nil

        if link_text.strip == url
          @markdown << url
        else
          @markdown << "[#{link_text}](#{url})"
        end
      end
    end

    def visit_EMAIL(node)
      @markdown << (start?(node) ? '<' : '>')
    end

    def visit_br(node)
      if @consecutive_br_count > 2
        @markdown << "<br>\n"
      else
        @markdown << "\n"
      end
    end

    # node for "BBCode start tag"
    def visit_s(node)
      ignore_node(node)
    end

    # node for "BBCode end tag"
    def visit_e(node)
      ignore_node(node)
    end

    # node for "ignored text"
    def visit_i(node)
      ignore_node(node)
    end

    def start?(node)
      node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    end

    def text?(node)
      node.node_type == Nokogiri::XML::Reader::TYPE_TEXT
    end

    def ignore_node(node)
      @ignore_node_count += start?(node) ? 1 : -1
    end

    def calc_consecutive_br_count(node)
      return unless start?(node) || text?(node)

      if node.name == 'br'
        @consecutive_br_count += 1
      else
        @consecutive_br_count = 0
      end
    end

    def text(node, escape_markdown: true)
      text = CGI.unescapeHTML(node.outer_xml)
      # text.gsub!(/[\\`*_{}\[\]()#+\-.!~]/) { |c| "\\#{c}" } if escape_markdown
      text
    end
  end
end
