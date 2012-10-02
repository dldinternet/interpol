require 'interpol/request_params_parser'

module Interpol
  module Sinatra
    # Parses and validates a sinatra params hash based on the
    # endpoint definitions.
    # Note that you use this like a sinatra middleware
    # (using a `use` directive in the body of the sinatra class), but
    # it hooks into sinatra differently so that it has access to the params.
    # It's more like a mix-in, honestly, but we piggyback on `use` so that
    # it can take a config block.
    class RequestParamsParser
      def initialize(app, &block)
        @app = app
        hook_into(app, &block)
      end

      def call(env)
        @app.call(env)
      end

      ConfigurationError = Class.new(StandardError)

    private

      def hook_into(app, &block)
        return if defined?(app.settings.interpol_config)
        check_configuration_validity(app)

        config = Configuration.default.customized_duplicate(&block)

        app.class.class_eval do
          alias unparsed_params params
          helpers SinatraHelpers
          set :interpol_config, config
          enable :parse_params unless settings.respond_to?(:parse_params)
          include SinatraOverriddes
        end
      end

      def check_configuration_validity(app)
        return if app.class.ancestors.include?(::Sinatra::Base)

        raise ConfigurationError, "#{self.class} must come last in the Sinatra " +
                                  "middleware list but #{app.class} currently comes after."
      end

      module SinatraHelpers
        # Make the config available at the instance level for convenience.
        def interpol_config
          self.class.interpol_config
        end

        def endpoint_definition
          @endpoint_definition ||= begin
            version = available_versions = nil

            definition = interpol_config.endpoints.find_definition \
              env.fetch('REQUEST_METHOD'), request.path, 'request', nil do |endpoint|
                available_versions ||= endpoint.available_versions
                interpol_config.api_version_for(env, endpoint).tap do |_version|
                  version ||= _version
                end
              end

            if definition == DefinitionFinder::NoDefinitionFound
              interpol_config.request_version_unavailable(self, version, available_versions)
            end

            definition
          end
        end

        def params
          (@_use_parsed_params && @_parsed_params) || super
        end

        def validate_params
          @_parsed_params ||= endpoint_definition.parse_request_params(params_to_parse)
        rescue Interpol::ValidationError => error
          request_params_invalid(error)
        end

        def request_params_invalid(error)
          interpol_config.sinatra_request_params_invalid(self, error)
        end

        def with_parsed_params
          @_use_parsed_params = true
          validate_params if settings.parse_params?
          yield
        ensure
          @_use_parsed_params = false
        end

        # Sinatra includes a couple of "meta" params that are always
        # present in the params hash even though they are not declared
        # as params: splat and captures.
        def params_to_parse
          unparsed_params.dup.tap do |p|
            p.delete('splat')
            p.delete('captures')
          end
        end
      end

      module SinatraOverriddes
        # We cannot access the full params (w/ path params) in a before hook,
        # due to the order that sinatra runs the hooks in relation to route
        # matching.
        def process_route(*method_args, &block)
          return super unless SinatraOverriddes.being_processed_by_sinatra?(block)

          super do |*block_args|
            with_parsed_params do
              yield *block_args
            end
          end
        end

        def self.being_processed_by_sinatra?(block)
          # In case the block is nil or we're on 1.8 w/o #source_location...
          # Just assume the route is being processed by sinatra.
          # It's an exceptional case for it to not be (e.g. NewRelic's
          # Sinatra hook).
          return true unless block.respond_to?(:source_location)
          block.source_location.first.end_with?('sinatra/base.rb')
        end
      end
    end
  end
end
