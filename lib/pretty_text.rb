require 'coffee_script'
require 'nokogiri'

if RUBY_PLATFORM =~ /java/
  require "rhino"
else
  require "v8"
end

module PrettyText

  def self.whitelist
    {
      :elements => %w[
        a abbr aside b bdo blockquote br caption cite code col colgroup dd div del dfn dl
        dt em hr figcaption figure h1 h2 h3 h4 h5 h6 hgroup i img ins kbd li mark
        ol p pre q rp rt ruby s samp small span strike strong sub sup table tbody td
        tfoot th thead time tr u ul var wbr
      ],

      :attributes => {
        :all         => ['dir', 'lang', 'title', 'class'],
        'aside'      => ['data-post', 'data-full', 'data-topic'],
        'a'          => ['href'],
        'blockquote' => ['cite'],
        'col'        => ['span', 'width'],
        'colgroup'   => ['span', 'width'],
        'del'        => ['cite', 'datetime'],
        'img'        => ['align', 'alt', 'height', 'src', 'width'],
        'ins'        => ['cite', 'datetime'],
        'ol'         => ['start', 'reversed', 'type'],
        'q'          => ['cite'],
        'span'       => ['style'],
        'table'      => ['summary', 'width', 'style', 'cellpadding', 'cellspacing'],
        'td'         => ['abbr', 'axis', 'colspan', 'rowspan', 'width', 'style'],
        'th'         => ['abbr', 'axis', 'colspan', 'rowspan', 'scope', 'width', 'style'],
        'time'       => ['datetime', 'pubdate'],
        'ul'         => ['type']
      },

      :protocols => {
        'a'          => {'href' => ['ftp', 'http', 'https', 'mailto', :relative]},
        'blockquote' => {'cite' => ['http', 'https', :relative]},
        'del'        => {'cite' => ['http', 'https', :relative]},
        'img'        => {'src'  => ['http', 'https', :relative]},
        'ins'        => {'cite' => ['http', 'https', :relative]},
        'q'          => {'cite' => ['http', 'https', :relative]}
      }
    }     
  end


  class Helpers
    # function here are available to v8 
    def avatar_template(username)
      return "" unless username

      user = User.where(username_lower: username.downcase).first
      if user
        user.avatar_template
      end
    end

    def is_username_valid(username)
      return false unless username
      username = username.downcase
      return User.exec_sql('select 1 from users where username_lower = ?', username).values.length == 1
    end
  end

  @mutex = Mutex.new

  def self.mention_matcher
    /(\@[a-zA-Z0-9\-]+)/
  end  

  def self.app_root
    Rails.root
  end

  def self.js
    return @ctx unless @ctx.nil?

    if RUBY_PLATFORM =~ /java/
      @ctx = Rhino::Context.new
    else
      @ctx = V8::Context.new
    end
    
    @ctx["helpers"] = Helpers.new 

    @ctx.load(File.join(app_root, "app/assets/javascripts/external/Markdown.Converter.js"))
    @ctx.load(File.join(app_root, "app/assets/javascripts/external/twitter-text-1.5.0.js"))
    @ctx.load(File.join(app_root, "lib/headless-ember.js"))
    @ctx.load(File.join(app_root, "app/assets/javascripts/external/rsvp.js"))
    @ctx.load(Rails.configuration.ember.handlebars_location.to_s)
    #@ctx.load(Rails.configuration.ember.ember_location.to_s)

    @ctx.load(File.join(app_root, "app/assets/javascripts/external/sugar-1.3.5.js"))
    @ctx.eval("var Discourse = {}; Discourse.SiteSettings = #{SiteSetting.client_settings_json};")
    @ctx.eval("var window = {}; window.devicePixelRatio = 2;") # hack to make code think stuff is retina

    @ctx.eval(CoffeeScript.compile(File.read(app_root + "app/assets/javascripts/discourse/components/bbcode.js.coffee")))
    @ctx.eval(CoffeeScript.compile(File.read(app_root + "app/assets/javascripts/discourse/components/utilities.coffee")))

    # Load server side javascripts
    if DiscoursePluginRegistry.server_side_javascripts.present?
      DiscoursePluginRegistry.server_side_javascripts.each do |ssjs|
        @ctx.load(ssjs.to_s)
      end
    end

    @ctx['quoteTemplate'] = File.open(app_root + 'app/assets/javascripts/discourse/templates/quote.js.shbrs') {|f| f.read}
    @ctx['quoteEmailTemplate'] = File.open(app_root + 'lib/assets/quote_email.js.shbrs') {|f| f.read}
    @ctx.eval("HANDLEBARS_TEMPLATES = { 
      'quote': Handlebars.compile(quoteTemplate),
      'quote_email': Handlebars.compile(quoteEmailTemplate),
     };")
    @ctx
  end

  def self.markdown(text, opts=nil)
    # we use the exact same markdown converter as the client
    # TODO: use the same extensions on both client and server (in particular the template for mentions) 
    
    baked = nil

    @mutex.synchronize do
      # we need to do this to work in a multi site environment, many sites, many settings
      js.eval("Discourse.SiteSettings = #{SiteSetting.client_settings_json};")
      js.eval("Discourse.BaseUrl = 'http://#{RailsMultisite::ConnectionManagement.current_hostname}';")
      js['opts'] = opts || {}
      js['raw'] = text
      js.eval('opts["mentionLookup"] = function(u){return helpers.is_username_valid(u);}')
      js.eval('opts["lookupAvatar"] = function(p){return Discourse.Utilities.avatarImg({username: p, size: "tiny", avatarTemplate: helpers.avatar_template(p)});}')
      baked = js.eval('Discourse.Utilities.markdownConverter(opts).makeHtml(raw)') 
    end

    # we need some minimal server side stuff, apply CDN and TODO filter disallowed markup
    baked = apply_cdn(baked, Rails.configuration.action_controller.asset_host)  
    baked
  end

  # leaving this here, cause it invokes v8, don't want to implement twice
  def self.avatar_img(username, size)
    r = nil
    @mutex.synchronize do        
      js['username'] = username
      js['size'] = size
      js.eval("Discourse.SiteSettings = #{SiteSetting.client_settings_json};")
      js.eval("Discourse.CDN = '#{Rails.configuration.action_controller.asset_host}';")
      js.eval("Discourse.BaseUrl = '#{RailsMultisite::ConnectionManagement.current_hostname}';")
      r = js.eval("Discourse.Utilities.avatarImg({ username: username, size: size });") 
    end
    r
  end

  def self.apply_cdn(html, url)
    return html unless url

    image = /\.(jpg|jpeg|gif|png|tiff|tif)$/

    doc = Nokogiri::HTML.fragment(html)
    doc.css("a").each do |l|
      href = l.attributes["href"].to_s
      if href[0] == '/' && href =~ image
        l["href"] = url + href
      end
    end
    doc.css("img").each do |l|
      src = l.attributes["src"].to_s
      if src[0] == '/' 
        l["src"] = url + src
      end
    end

    doc.to_s
  end

  def self.cook(text, opts={})
    cloned = opts.dup
    # we have a minor inconsistency
    cloned[:topicId] = opts[:topic_id]
    sanitized = Sanitize.clean(markdown(text.dup, cloned), PrettyText.whitelist)    
    if SiteSetting.add_rel_nofollow_to_user_content
      sanitized = add_rel_nofollow_to_user_content(sanitized) 
    end
    sanitized
  end
  
  def self.add_rel_nofollow_to_user_content(html)
    whitelist = []

    l = SiteSetting.exclude_rel_nofollow_domains
    if l.present?
      whitelist = l.split(",") 
    end

    site_uri = nil
    doc = Nokogiri::HTML.fragment(html)
    doc.css("a").each do |l|
      href = l["href"].to_s
      begin 
        uri = URI(href)
        site_uri ||= URI(Discourse.base_url)
        
        if  !uri.host.present? || 
            uri.host.ends_with?(site_uri.host) || 
            whitelist.any?{|u| uri.host.ends_with?(u)}
          # we are good no need for nofollow
        else
          l["rel"] = "nofollow"
        end
      rescue URI::InvalidURIError
        # add a nofollow anyway 
        l["rel"] = "nofollow"
      end
    end
    doc.to_html
  end

  def self.extract_links(html)
    doc = Nokogiri::HTML.fragment(html)
    links = []
    doc.css("a").each do |l|
      links << l.attributes["href"].to_s
    end

    doc.css("aside.quote").each do |a|
      topic_id = a.attributes['data-topic']
      
      url = "/t/topic/#{topic_id}"
      if post_number = a.attributes['data-post']
        url << "/#{post_number}"
      end

      links << url
    end

    links
  end

  class ExcerptParser < Nokogiri::XML::SAX::Document

    class DoneException < StandardError; end 

    attr_reader :excerpt

    def initialize(length)
      @length = length 
      @excerpt = ""
      @current_length = 0
    end

    def self.get_excerpt(html, length)
      me = self.new(length)
      parser = Nokogiri::HTML::SAX::Parser.new(me)
      begin 
        copy = "<div>" 
        copy << html unless html.nil?
        copy << "</div>"
        parser.parse(html) unless html.nil?
      rescue DoneException
        # we are done 
      end
      me.excerpt
    end

    def start_element(name, attributes=[])
      case name 
        when "img"
          attributes = Hash[*attributes.flatten]
          if attributes["alt"]
            characters("[#{attributes["alt"]}]")
          elsif attributes["title"]
            characters("[#{attributes["title"]}]")
          else
            characters("[image]")
          end
        when "a"
          c = "<a "
          c << attributes.map{|k,v| "#{k}='#{v}'"}.join(' ')
          c << ">"
          characters(c, false, false, false)
          @in_a = true
        when "aside"
          @in_quote = true 
      end
    end

    def end_element(name)
      case name 
      when "a"
        characters("</a>",false, false, false)
        @in_a = false
      when "p", "br"
        characters(" ")
      when "aside"
        @in_quote = false
      end
    end

    def characters(string, truncate = true, count_it = true, encode = true)
      return if @in_quote
      encode = encode ? lambda{|s| ERB::Util.html_escape(s)} : lambda {|s| s} 
      if @current_length + string.length > @length && count_it
        @excerpt << encode.call(string[0..(@length-@current_length)-1]) if truncate
        @excerpt << "&hellip;"
        @excerpt << "</a>" if @in_a
        raise DoneException.new
      end
      @excerpt << encode.call(string)
      @current_length += string.length if count_it
    end
  end

  def self.excerpt(html, length)
    ExcerptParser.get_excerpt(html, length)
  end

end

