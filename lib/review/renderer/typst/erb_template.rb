# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'erb'

module ReVIEW
  module Renderer
    module Typst
      # Renders one of the bundled ERB templates.
      #
      # The templates read each value as a bare method name, so the values are
      # exposed as singleton methods on a throwaway object rather than as
      # instance variables of whatever happens to be rendering.
      module ErbTemplate
        module_function

        # @param template [String] ERB source
        # @param locals [Hash] Values the template refers to by name
        # @return [String]
        def render(template, **locals)
          scope = Object.new
          locals.each { |name, value| scope.define_singleton_method(name) { value } }
          ERB.new(template, trim_mode: '-').result(scope.instance_eval { binding })
        end
      end
    end
  end
end
