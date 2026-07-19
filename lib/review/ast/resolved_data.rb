# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # ResolvedData - Immutable data structure holding resolved reference information
    #
    # This class contains structured data about resolved references,
    # separating the logical resolution (what is being referenced)
    # from the presentation (how it should be displayed).
    class ResolvedData
      # Ordered field declaration for a reference type.
      #
      # A subclass declares only the fields it actually has, and that single
      # declaration drives the readers, ==, serialization and deserialization.
      # Before this, the base class enumerated the union of every subclass's
      # fields in three separate places, so adding a reference type meant
      # editing the base as well as writing the subclass.
      #
      # Declaration order is the serialization order, so it is also the key
      # order of the dump; keep it stable when editing.
      #
      # Kinds: :plain (round-trips as-is), :symbol (restored with to_sym),
      # :node (an AST node, serialized/restored through JSONSerializer).
      #
      #   fields :chapter_number, :item_id, chapter_type: :symbol, caption_node: :node
      def self.fields(*plain, **typed)
        declarations = {}
        plain.each { |name| declarations[name] = :plain }
        typed.each { |name, kind| declarations[name] = kind }
        @field_declarations = declarations
        attr_reader(*declarations.keys)
      end

      # The declarations for this class, inherited when a subclass adds none.
      def self.field_declarations
        return @field_declarations if @field_declarations
        return {} unless superclass.respond_to?(:field_declarations)

        superclass.field_declarations
      end

      # Get caption text from caption_node
      # @return [String] Caption text, empty string if no caption_node
      def caption_text
        caption_node&.to_inline_text || ''
      end

      # Whether the reference names a chapter explicitly. The resolver only sets
      # chapter_id for a reference written with a chapter qualifier, so this is
      # "was a chapter named", not "does it point outside the current chapter".
      # ReferenceNode#cross_chapter? answers the same question from context_id.
      def cross_chapter?
        !@chapter_id.nil?
      end

      # Helper methods for chapter type checking
      # @return [Boolean] true if the referenced chapter is a regular chapter
      def chapter?
        @chapter_type == :chapter
      end

      # @return [Boolean] true if the referenced chapter is an appendix
      def appendix?
        @chapter_type == :appendix
      end

      # @return [Boolean] true if the referenced chapter is a part
      def part?
        @chapter_type == :part
      end

      def ==(other)
        return false unless other.instance_of?(self.class)

        self.class.field_declarations.each_key.all? do |name|
          public_send(name) == other.public_send(name)
        end
      end

      alias_method :eql?, :==

      def to_s
        parts = ['#<ResolvedData']
        parts << "chapter=#{@chapter_number}" if @chapter_number
        parts << "item=#{@item_number}" if @item_number
        parts << "chapter_id=#{@chapter_id}" if @chapter_id
        parts << "item_id=#{@item_id}"
        parts << "type=#{@chapter_type}" if @chapter_type
        parts.join(' ') + '>'
      end

      # Serialize to hash
      # @param options [JSONSerializer::Options, nil] Serialization options
      # @return [Hash] Serialized hash representation
      def serialize_to_hash(options = nil)
        options ||= ReVIEW::AST::JSONSerializer::Options.new
        hash = { type: self.class.name.split('::').last }
        serialize_properties(hash, options)
        hash
      end

      # Serialize the declared fields, in declaration order. Nil fields are
      # omitted, so a type only emits the keys it actually carries.
      # @param hash [Hash] Hash to populate with properties
      # @param options [JSONSerializer::Options] Serialization options
      # @return [Hash] Populated hash
      def serialize_properties(hash, options)
        self.class.field_declarations.each do |name, kind|
          value = public_send(name)
          next if value.nil?

          hash[name] = kind == :node ? value.serialize_to_hash(options) : value
        end
        hash
      end

      # On ResolvedData itself this dispatches to the concrete type named in the
      # hash; on a subclass it builds that subclass from its declared fields.
      # A subclass with a shape the declarations cannot express overrides this.
      # @param hash [Hash] Hash to deserialize from
      # @return [ResolvedData] Deserialized ResolvedData instance
      def self.deserialize_from_hash(hash)
        return nil unless hash
        return build_from_declarations(hash) unless self == ResolvedData

        type = hash['type']
        return nil unless type

        begin
          klass = const_get(type)
        rescue NameError
          raise StandardError, "Unknown ResolvedData type: #{type}"
        end

        klass.deserialize_from_hash(hash)
      end

      # Build an instance from the declared fields. Only keywords the
      # constructor accepts are passed; a required keyword absent from the hash
      # is passed as nil so that a field which was nil (and therefore omitted by
      # serialize_properties) still round-trips.
      # @param hash [Hash] Hash to build from
      # @return [ResolvedData] The built instance
      def self.build_from_declarations(hash)
        declarations = field_declarations
        args = {}

        constructor_keywords.each do |name, required|
          next unless hash.key?(name.to_s) || required

          args[name] = restore_field(hash[name.to_s], declarations[name])
        end

        new(**args)
      end

      # The constructor's keyword parameters as {name => required?}.
      # @return [Hash{Symbol => Boolean}]
      def self.constructor_keywords
        instance_method(:initialize).parameters.each_with_object({}) do |(kind, name), keywords|
          keywords[name] = (kind == :keyreq) if %i[key keyreq].include?(kind)
        end
      end

      # @param value [Object] Raw value from the hash
      # @param kind [Symbol, nil] Declared kind of the field
      # @return [Object] Value restored to its in-memory form
      def self.restore_field(value, kind)
        return nil if value.nil?

        case kind
        when :symbol then value.to_sym
        when :node then ReVIEW::AST::JSONSerializer.deserialize_from_hash(value)
        else value
        end
      end

      private_class_method :build_from_declarations, :constructor_keywords, :restore_field

      # Get the reference type for this resolved data
      # @return [Symbol] Reference type (e.g., :image, :table, :list)
      def reference_type
        raise NotImplementedError, "#{self.class}#reference_type must be implemented"
      end

      # Factory methods for common reference types

      def self.image(chapter_number:, item_number:, item_id:, chapter_id: nil, chapter_type: nil, caption_node: nil)
        ImageReference.new(
          chapter_number: chapter_number,
          item_number: item_number,
          chapter_id: chapter_id,
          item_id: item_id,
          chapter_type: chapter_type,
          caption_node: caption_node
        )
      end

      def self.table(chapter_number:, item_number:, item_id:, chapter_id: nil, chapter_type: nil, caption_node: nil)
        TableReference.new(
          chapter_number: chapter_number,
          item_number: item_number,
          chapter_id: chapter_id,
          item_id: item_id,
          chapter_type: chapter_type,
          caption_node: caption_node
        )
      end

      def self.list(chapter_number:, item_number:, item_id:, chapter_id: nil, chapter_type: nil, caption_node: nil)
        ListReference.new(
          chapter_number: chapter_number,
          item_number: item_number,
          chapter_id: chapter_id,
          item_id: item_id,
          chapter_type: chapter_type,
          caption_node: caption_node
        )
      end

      def self.equation(chapter_number:, item_number:, item_id:, chapter_type: nil, caption_node: nil)
        EquationReference.new(
          chapter_number: chapter_number,
          item_number: item_number,
          item_id: item_id,
          chapter_type: chapter_type,
          caption_node: caption_node
        )
      end

      def self.footnote(item_number:, item_id:, caption_node: nil)
        FootnoteReference.new(
          item_number: item_number,
          item_id: item_id,
          caption_node: caption_node
        )
      end

      def self.endnote(item_number:, item_id:, caption_node: nil)
        EndnoteReference.new(
          item_number: item_number,
          item_id: item_id,
          caption_node: caption_node
        )
      end

      def self.chapter(chapter_number:, chapter_id:, item_id:, chapter_title: nil, caption_node: nil, chapter_type: nil)
        ChapterReference.new(
          chapter_number: chapter_number,
          chapter_id: chapter_id,
          item_id: item_id,
          chapter_title: chapter_title,
          caption_node: caption_node,
          chapter_type: chapter_type
        )
      end

      def self.headline(headline_number:, item_id:, chapter_id: nil, chapter_number: nil, chapter_type: nil, caption_node: nil)
        HeadlineReference.new(
          item_id: item_id,
          chapter_id: chapter_id,
          chapter_number: chapter_number,
          headline_number: headline_number, # Array format [1, 2, 3]
          chapter_type: chapter_type,
          caption_node: caption_node
        )
      end

      def self.word(word_content:, item_id:, caption_node: nil)
        WordReference.new(
          item_id: item_id,
          word_content: word_content,
          caption_node: caption_node
        )
      end

      def self.column(chapter_number:, item_number:, item_id:, chapter_id: nil, chapter_type: nil, caption_node: nil)
        ColumnReference.new(
          chapter_number: chapter_number,
          item_number: item_number,
          chapter_id: chapter_id,
          item_id: item_id,
          chapter_type: chapter_type,
          caption_node: caption_node
        )
      end

      def self.bibpaper(item_number:, item_id:, caption_node: nil)
        BibpaperReference.new(
          item_number: item_number,
          item_id: item_id,
          caption_node: caption_node
        )
      end
    end
  end
end

# Require nested class files
require_relative 'resolved_data/captioned_item_reference'
require_relative 'resolved_data/image_reference'
require_relative 'resolved_data/table_reference'
require_relative 'resolved_data/list_reference'
require_relative 'resolved_data/equation_reference'
require_relative 'resolved_data/footnote_reference'
require_relative 'resolved_data/endnote_reference'
require_relative 'resolved_data/chapter_reference'
require_relative 'resolved_data/headline_reference'
require_relative 'resolved_data/word_reference'
require_relative 'resolved_data/column_reference'
require_relative 'resolved_data/bibpaper_reference'
