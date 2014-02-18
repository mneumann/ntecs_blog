require 'toml'
require 'yaml'
require 'tilt'
require 'kramdown'
require 'erb'
require 'tilt/erb'
require 'fileutils'

class Site
  attr_accessor :title, :contentdir, :outdir

  def initialize(title, contentdir, outdir)
    @title, @contentdir, @outdir = title, contentdir, outdir
  end
end

class String
  def to_permalink
    self.gsub(/[^a-zA-Z0-9]/, " ").downcase.gsub(/\s+/, " ").strip.gsub(/\s+/, "-")
  end
end

def write_file(filename, data)
  raise if File.exist?(filename)
  File.write(filename, data)
end

# Only support Markdown documents for now
class Document

  # relpath is relative to the Site's contentdir
  attr_accessor :relpath

  attr_accessor :frontmatter, :raw_content

  def initialize(relpath, frontmatter, raw_content)
    raise if relpath.start_with?("/") or relpath.start_with?(".")
    @relpath, @frontmatter, @raw_content = relpath, frontmatter, raw_content
    @content = Kramdown::Document.new(@raw_content).to_html
  end

  def date
    @frontmatter["date"] || raise
  end

  def title
    @frontmatter["title"]
  end

  def content
    @content || raise
  end

  def render(site, template)
    template.render(self, :page => self, :site => site)
  end

  private def permalink_ary
    dir = File.dirname(@relpath)
    base = File.basename(@relpath)
    ext = File.extname(base)
    name = base[0, base.size - ext.size] 

    section = dir.split("/").first  # XXX: Not portable

    title = self.title || name

    slug = %w(%Y %m %d).map {|fmt| self.date.strftime(fmt) }

    [section, *slug, title.to_permalink]
  end

  def permalink
    "/" + permalink_ary().join("/") + "/"
  end

  # Which path to generate for this file
  def outrelpath
    File.join(*permalink_ary(), "index.html")
  end

  def outreldir
    File.dirname(self.outrelpath)
  end

  def self.parse(site, relpath)
    data = File.read(File.join(site.contentdir, relpath))
    lines = data.lines
    first_line = lines.first.chomp

    unless first_line == "+++" or first_line == "---"
      # no recognized frontmatter
      return new(relpath, {}, data)
    end

    frontmatter = []
    markup = []

    in_frontmatter = true

    lines[1..-1].each {|line|
      line.chomp!

      if in_frontmatter
        if line == first_line
          in_frontmatter = false
        else
          frontmatter << line
        end
      else
        markup << line
      end
    }

    klass = case first_line 
            when "+++" then TOML
            when "---" then YAML
            else raise end

    new(relpath, klass::load(frontmatter.join("\n")), markup.join("\n"))
  end
end

site = Site.new('NTECS Blog', 'content', '_site')

documents = Dir.chdir(site.contentdir) { Dir["**/*.md"] }.map {|relpath|
  Document.parse(site, relpath)
}

template = Tilt::ERBTemplate.new('layouts/post/single.html.erb')

documents.each do |doc|
  outpath = File.join(site.outdir, doc.outrelpath)
  FileUtils.mkdir_p(File.join(site.outdir, doc.outreldir))
  write_file(outpath, doc.render(site, template))
  puts "Writing: #{outpath}"
end

puts "Generate index"

index = Tilt::ERBTemplate.new('layouts/indexes/post.html.erb')
page_template = Tilt::ERBTemplate.new('layouts/post/index.html.erb')

write_file(File.join(site.outdir, "index.html"),
           index.render(self, :pages => documents, :site => site, :template => page_template))

if ARGV.shift == 'serve'
  require 'webrick'
  WEBrick::HTTPServer.new(:Port => 1313, :DocumentRoot => site.outdir).start
end
