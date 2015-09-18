require 'blockenspiel'
require 'singleton'
require 'carnivore/utils'

module Carnivore
  module Http

    # End point builder
    class PointBuilder

      # End point
      class Endpoint

        include Zoidberg::SoftShell
        include Zoidberg::Supervise
        include Carnivore::Utils::Params
        include Carnivore::Utils::Logging

        # @return [String, Regexp] request path matcher
        attr_reader :endpoint
        # @return [Symbol] request type (:get, :put, etc.)
        attr_reader :type

        # Create new endoint
        #
        # @param type [Symbol] request type (:get, :put, etc.)
        # @param endpoint [String, Regexp] request path matcher
        # @param block [Proc] action to run on match
        def initialize(type, endpoint, block)
          @endpoint = endpoint
          @type = type
          define_singleton_method(:wrapped_execute, &block)
        end

        # Execute action on match
        #
        # @param args [Object] argument list
        def execute(*args)
          begin
            wrapped_execute(*args)
          rescue => e
            error "Unexpected error encountered! #{e.class}: #{e}"
            debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
            abort e
          end
        end

        # @return [String] stringify
        def to_s
          "<Endpoint[#{endpoint}]>"
        end

        # @return [String] instance inspection
        def inspect
          "<Endpoint[#{endpoint}] type=#{type} objectid=#{self.object_id}>"
        end

      end

      include Carnivore::Utils::Params
      include Carnivore::Utils::Logging
      include Blockenspiel::DSL

      # @return [Hash] static path endpoints
      attr_reader :static
      # @return [Hash] regex path endpoints
      attr_reader :regex
      # @return [Array] only enable endpoints
      attr_reader :only
      # @return [Array] do not enable endpoints
      attr_reader :except
      # @return [Carnivore::Supervisor] supervisor
      attr_reader :endpoint_supervisor

      # Create new instance
      #
      # @param args [Hash]
      # @option args [Array] :only
      # @option args [Array] :except
      def initialize(args={})
        @only = args[:only]
        @except = args[:except]
        @static = {}
        @regex = {}
        @callback_names = {}
        @endpoint_supervisor = Carnivore::Supervisor.create!.last
        load_endpoints!
      end

      # Request methods
      # @todo add yardoc method generation
      [:get, :put, :post, :delete, :head, :options, :trace].each do |name|
        define_method(name) do |regexp_or_string, args={}, &block|
          endpoint(name, regexp_or_string, args, &block)
        end
      end

      dsl_methods false

      # Deliver message to end points
      #
      # @param msg [Carnivore::Message]
      # @return [Truthy, Falsey]
      def deliver(msg)
        type = msg[:message][:request].method.to_s.downcase.to_sym
        path = msg[:message][:request].url
        static_points(msg, type, path) || regex_points(msg, type, path)
      end

      # Apply message to static endpoints and execute if matching
      #
      # @param msg [Carnivore::Message]
      # @param type [Symbol] request type
      # @param path [String] request path
      # @param [Truthy, Falsey] match was detected and executed
      def static_points(msg, type, path)
        if(static[type])
          match = static[type].keys.detect do |point|
            !path.scan(/^#{Regexp.escape(point)}\/?(\?|$)/).empty?
          end
          if(match)
            if(static[type][match][:async])
              endpoint_supervisor[callback_name(match, type)].async.execute(msg)
              true
            else
              endpoint_supervisor[callback_name(match, type)].execute(msg)
              true
            end
          end
        end
      end

      # Apply message to regex endpoints and execute if matching
      #
      # @param msg [Carnivore::Message]
      # @param type [Symbol] request type
      # @param path [String] request path
      # @param [Truthy, Falsey] match was detected and executed
      def regex_points(msg, type, path)
        if(regex[type])
          match = regex[type].keys.map do |point|
            unless((res = path.scan(/^(#{point})(\?|$)/)).empty?)
              res = res.first
              res.pop # remove empty EOS match
              [point, res]
            end
          end.compact.first
          if(match && !match.empty?)
            if(regex[type][match.first][:async])
              endpoint_supervisor[callback_name(match.first, type)].async.execute(*([msg] + match.last))
              true
            else
              endpoint_supervisor[callback_name(match.first, type)].execute(*([msg] + match.last))
              true
            end
          end
        end
      end

      # Generate internal callback name reference
      #
      # @param point [String, Symbol]
      # @param type [String, Symbol]
      # @return [String]
      def callback_name(point, type)
        key = "#{point}_#{type}"
        unless(@callback_names[key])
          @callback_names[key] = Digest::SHA256.hexdigest(key)
        end
        @callback_names[key]
      end

      # Build new endpoint and supervise
      #
      # @param request_type [Symbol, String] request type (:get, :put, etc.)
      # @param regexp_or_string [Regexp, String]
      # @param args [Hash]
      # @option args [Numeric] :workers number of workers to initialize
      # @yield action to execute on match
      def endpoint(request_type, regexp_or_string, args, &block)
        request_type = request_type.to_sym
        if(regexp_or_string.is_a?(Regexp))
          regex[request_type] ||= {}
          regex[request_type][regexp_or_string] = args
        else
          static[request_type] ||= {}
          static[request_type][regexp_or_string.sub(%r{/$}, '')] = args
        end
        if(args[:workers] && args[:workers].to_i > 1)
          endpoint_supervisor.pool(Endpoint,
            as: callback_name(regexp_or_string, request_type), size: args[:workers].to_i,
            args: [request_type, regexp_or_string, block]
          )
        else
          endpoint_supervisor.supervise_as(
            callback_name(regexp_or_string, request_type), Endpoint, request_type, regexp_or_string, block
          )
        end
        true
      end

      # @return [Array] all endpoints
      def endpoints
        [static, regex]
      end

      private

      # Load all available endpoints
      #
      # @note will register all discoverable subclasses
      def load_endpoints!
        self.class.compress_offspring.each do |name, block|
          next if only && !only.include?(name.to_s)
          next if except && except.include?(name.to_s)
          Blockenspiel.invoke(block, self)
        end
        true
      end

      class << self

        # Store subclass reference in descendants and
        # setup properly for DSL usage
        #
        # @param klass [Class]
        def inherited(klass)
          descendants.push(klass)
        end

        # Define new API block
        #
        # @yield new API block
        def define(&block)
          store(Zoidberg.uuid, block)
        end

        # Store block
        #
        # @param name [String, Symbol]
        # @param block [Proc]
        def store(name, block)
          storage[name.to_sym] = block
          self
        end

        # @return [Hash] storage for defined blocks
        def storage
          @storage ||= {}
        end

        # @return [Array<Class>] descendant classes
        def descendants
          @descendants ||= []
        end

        # @return [Array<Hash>] all descendant storages (full tree)
        def offspring_storage
          descendants.map(&:offspring_storage).flatten.unshift(storage)
        end

        # @return [Hash] merged storages (full tree)
        def compress_offspring
          stores = offspring_storage
          stores.inject(stores.shift) do |memo, store|
            memo.merge(store)
          end
        end

      end
    end
  end
end

# Alias for previous release compatibility
Carnivore::PointBuilder = Carnivore::Http::PointBuilder
