require 'rdf/linter/writer'
require 'rdf/linter/vocab_defs'
require 'nokogiri'

module RDF::Linter
  module Parser

    # Parse the an input file and re-serialize based on params and/or content-type/accept headers
    def parse(reader_opts)
      graph = RDF::Graph.new
      format = reader_opts[:format]
      reader_opts[:prefixes] ||= {}
      reader_opts[:rdf_terms] = true unless reader_opts.has_key?(:rdf_terms)

      reader = case
      when reader_opts[:tempfile]
        RDF::Reader.for(format).new(reader_opts[:tempfile], reader_opts) {|r| graph << r}
      when  reader_opts[:content]
        @content = reader_opts[:content]
        RDF::Reader.for(format).new(@content, reader_opts) {|r| graph << r}
      when reader_opts[:base_uri]
        RDF::Reader.open(reader_opts[:base_uri], reader_opts) {|r| graph << r}
      else
        return ["text/html", ""]
      end

      @parsed_statements = case reader
      when RDF::All::Reader
        reader.statement_count
      else
        {reader.class => graph.size }
      end
      
      # Perform some actual linting on the graph
      @lint_messages = lint(graph)

      # Special case for Facebook OGP. Facebook (apparently) doesn't believe in rdf:type,
      # so we look for statements with predicate og:type with a literal object and create
      # an rdf:type in a similar namespace
      graph.query(:predicate => RDF::URI("http://ogp.me/ns#type")) do |statement|
        graph << RDF::Statement.new(statement.subject, RDF.type, RDF::URI("http://types.ogp.me/ns##{statement.object}"))
      end
      
      # Similar, but using old namespace
      graph.query(:predicate => RDF::URI("http://opengraphprotocol.org/schema/type")) do |statement|
        graph << RDF::Statement.new(statement.subject, RDF.type, RDF::URI("http://opengraphprotocol.org/types/#{statement.object}"))
      end
      
      writer_opts = reader_opts
      writer_opts[:base_uri] ||= reader.base_uri.to_s if reader.base_uri
      writer_opts[:prefixes][:ogt] = "http://types.ogp.me/ns#"
      
      # Move elements with class `snippet` to the front of the root element
      html = RDF::Linter::Writer.buffer(writer_opts) {|w| w << graph}
      ["text/html", html]
    rescue RDF::ReaderError => e
      @error = "RDF::ReaderError: #{e.message}"
      puts @error  # to log
      ["text/html", @error]
    rescue OpenURI::HTTPError => e
      @error = "Failed to open #{reader_opts[:base_uri]}: #{e.message}"
      puts @error  # to log
      ["text/html", @error]
    rescue
      raise unless settings.environment == :production
      @error = "#{$!.class}: #{$!.message}"
      puts @error  # to log
      ["text/html", @error]
    end

    # Use vocabulary definitions to lint contents of the graph for known vocabularies
    def lint(graph)
      messages = {}
      graph.query(:predicate => RDF.type) do |st|
        cls = st.object.to_s
        pfx, uri = nil, nil
        VOCAB_DEFS["Vocabularies"].each do |k, v|
          pfx, uri = k, v if st.object.starts_with?(v)
        end
        if pfx && !VOCAB_DEFS["Classes"].has_key?(cls)
          # No type definition found for vocabulary
          messages[:class] ||= {}
          messages[:class][cls.sub(uri, "#{pfx}:")] = "No class definition found"
        end
      end

      graph.statements.map(&:predicate).uniq do |pred|
        prop = pred.to_s
        pfx, uri = nil, nil
        VOCAB_DEFS["Vocabularies"].each do |k, v|
          pfx, uri = k, v if prop.index(v) == 0
        end
        if pfx && !VOCAB_DEFS["Properties"].has_key?(prop)
          # No type definition found for vocabulary
          messages[:property] ||= {}
          messages[:property][prop.sub(uri, "#{pfx}:")] = "No property definition found"
        end
      end
      
      messages
    end
    
    # Create native representation of vocabulary definitions from JSON files
    def self.cook_vocabularies(io = STDOUT)
      require 'json'
      defs = {
        "Vocabularies" => {},
        "Classes" => {},
        "Properties" => {},
        "Datatypes" => {},
      }
      Dir.glob(File.join(File.dirname(__FILE__), "*.json")).each do |file|
        File.open(file) do |f|
          STDERR.puts "load #{file}"
          v = JSON.load(f)
          v.each do |sect, hash|
            raise "unknown section #{sect}" unless defs.has_key?(sect)
            v[sect].each do |name, defn|
              raise "attempt to redefine #{sect} definition of #{name}" if defs[sect].has_key?(name)
              defs[sect][name] = defn
            end
          end
        end
      end
    
      # Serialize definitions
      io.puts "# This file is automatically generated by #{__FILE__}"
      io.puts "module RDF::Linter::Parser"
      io.puts "  VOCAB_DEFS = " + defs.inspect
      io.puts "end"
    end
  end
end