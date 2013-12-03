module Carnivore
  module Http
    module Utils
      module Params

        class << self

          def included(klass)
            require 'cgi'
          end

        end

        # string:: HTTP query string
        # Return Hash of parsed query string
        def parse_query_string(string)
          unless(string.to_s.empty?)
            args = CGI.parse(string)
            format_query_args(args)
          else
            {}
          end
        end

        # args:: HTTP query string Hash
        # Return formatted hash with inferred types
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

        # obj:: object
        # Attempts to return true type
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
