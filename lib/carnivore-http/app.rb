require 'rack'
require 'timeout'
require 'carnivore-http'

module Carnivore
  module Http
    # Rack app for processing messages
    class App

      # Customized response
      class Response < Rack::Response

        # Lazy status mapping
        STATUS_CODES = Smash.new(
          "continue" => 100,
          "switching_protocols" => 101,
          "processing" => 102,
          "ok" => 200,
          "created" => 201,
          "accepted" => 202,
          "non_authoritative_information" => 203,
          "no_content" => 204,
          "reset_content" => 205,
          "partial_content" => 206,
          "multi_status" => 207,
          "already_reported" => 208,
          "im_used" => 226,
          "multiple_choices" => 300,
          "moved_permanently" => 301,
          "found" => 302,
          "see_other" => 303,
          "not_modified" => 304,
          "use_proxy" => 305,
          "temporary_redirect" => 307,
          "permanent_redirect" => 308,
          "bad_request" => 400,
          "unauthorized" => 401,
          "payment_required" => 402,
          "forbidden" => 403,
          "not_found" => 404,
          "method_not_allowed" => 405,
          "not_acceptable" => 406,
          "proxy_authentication_required" => 407,
          "request_timeout" => 408,
          "conflict" => 409,
          "gone" => 410,
          "length_required" => 411,
          "precondition_failed" => 412,
          "payload_too_large" => 413,
          "uri_too_long" => 414,
          "unsupported_media_type" => 415,
          "range_not_satisfiable" => 416,
          "expectation_failed" => 417,
          "misdirected_request" => 421,
          "unprocessable_entity" => 422,
          "locked" => 423,
          "failed_dependency" => 424,
          "upgrade_required" => 426,
          "precondition_required" => 428,
          "too_many_requests" => 429,
          "request_header_fields_too_large" => 431,
          "internal_server_error" => 500,
          "not_implemented" => 501,
          "bad_gateway" => 502,
          "service_unavailable" => 503,
          "gateway_timeout" => 504,
          "http_version_not_supported" => 505,
          "variant_also_negotiates" => 506,
          "insufficient_storage" => 507,
          "loop_detected" => 508,
          "not_extended" => 510,
          "network_authentication_required" => 511
        )

        # Create a new response
        #
        # @param code [String, Symbol, Integer] status code of response
        # @param string_or_args [String, Hash] response content
        # @option :body [String] response body
        # @option :json [Hash, Array] response body to serialize
        # @option :form [Hash] response body to encode
        # @option :headers [Hash] response headers
        # @return [self]
        def initialize(code, string_or_args, &block)
          status = STATUS_CODES.fetch(code, code).to_i
          case string_or_args
          when String
            body = string_or_args
            headers = {}
          when Hash
            headers = string_or_args.fetch(:headers, {})
            if(string_or_args[:body])
              body = string_or_args[:body]
              unless(headers['Content-Type'])
                headers['Content-Type'] = 'text/plain'
              end
            elsif(string_or_args[:json])
              body = MultiJson.dump(string_or_args[:json])
              unless(headers['Content-Type'])
                headers['Content-Type'] = 'application/json'
              end
            elsif(string_or_args[:form])
              body = dump_query_string(string_or_args[:form])
              unless(headers['Content-Type'])
                headers['Content-Type'] = 'application/x-www-form-urlencoded'
              end
            end
          else
            raise TypeError.new "Invalid type provided. Expected `String` or `Hash` but got `#{string_or_args.class}`"
          end
          super(body, status, headers, &block)
        end

      end


      # Customized request
      class Request < Rack::Request

        include Zoidberg::SoftShell

        option :cache_signals

        # @return [Response]
        attr_reader :response_value

        # Respond to the request
        #
        # @param code [String, Symbol, Integer] response status code
        # @param string_or_args [String, Hash]
        # @return [TrueClass, FalseClass]
        def respond(code, string_or_args='')
          unless(@response_value)
            signal(:response, Response.new(code, string_or_args))
          else
            raise 'Response was already set!'
          end
        end

        # Response to this request
        #
        # @param timeout [Integer] maximum number of seconds to wait
        # @return [Response]
        def response(timeout=5)
          unless(@response_value)
            begin
              Timeout.timeout(timeout) do
                @response_value = wait_for(:response)
              end
            rescue Timeout::Error
              @response_value = Response.new(:internal_server_error, 'Timeout waiting for response')
            end
          end
          @response_value
        end

        # @return [Smash]
        def headers
          Smash[
            env.map do |k,v|
              k.start_with?('rack.') ? nil : [k.downcase.sub(/^http_/, '').to_sym,v]
            end.compact
          ]
        end

        # @return [String]
        def remote_addr
          headers['REMOTE_ADDR']
        end

        # @return [Symbol]
        def method
          request_method.to_s.downcase.to_sym
        end

      end

      # @return [Proc] action to process request
      attr_reader :action

      # Create a new instance
      #
      # @param args [Hash]
      # @yield processes request
      # @return [self]
      def initialize(args={}, &block)
        @action = block
      end

      # Process the request
      #
      # @param env [Hash]
      # @return [Array]
      def call(env)
        request = Request.new(env)
        action.call(request)
        request.response.finish
      end

      class << self

        # Build a new app
        #
        # @param args [Hash] options
        # @param block [Proc]
        # @return [App]
        def build_app(args={}, &block)
          Rack::Builder.new do
            use Rack::Chunked
            run self.new(args, &block)
          end
        end

      end

    end
  end
end
