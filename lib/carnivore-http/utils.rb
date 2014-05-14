module Carnivore
  module Http

    # Helper utilities
    module Utils

      # URL parameter helpers
      module Params

        class << self

          # Load cgi library on demand
          #
          # @param klass [Class]
          def included(klass)
            require 'cgi'
          end

        end

        # Generate hash of parsed query String
        #
        # @param string [String] HTTP query string
        # @return [Hash]
        def parse_query_string(string)
          unless(string.to_s.empty?)
            args = CGI.parse(string)
            format_query_args(args)
          else
            {}
          end
        end

        # Cast hash values when possible
        #
        # @param args [Hash]
        # @return [Hash]
        def format_query_args(args)
          new_args = {}
          args.each do |k, v|
            k = k.to_sym
            case v
            when Hash
              new_args[k] = format_query_args(v)
            when Array
              v = v.map{|obj| format_query_type(obj)}
              new_args[k] = v.size == 1 ? v.first : v
            else
              new_args[k] = format_query_type(v)
            end
          end
          new_args
        end

        # Best attempt to convert to true type
        #
        # @param obj [Object] generally string value
        # @return [Object] result of best attempt
        def format_query_type(obj)
          case obj
          when 'true'
            true
          when 'false'
            false
          else
            if(obj.to_i.to_s == obj)
              obj.to_i
            elsif(obj.to_f.to_s == obj)
              obj.to_f
            else
              obj
            end
          end
        end

      end
    end
  end
end
