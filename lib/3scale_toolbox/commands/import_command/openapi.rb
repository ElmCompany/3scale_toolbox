require '3scale_toolbox/commands/import_command/openapi/method'
require '3scale_toolbox/commands/import_command/openapi/mapping_rule'
require '3scale_toolbox/commands/import_command/openapi/operation'
require '3scale_toolbox/commands/import_command/openapi/step'
require '3scale_toolbox/commands/import_command/openapi/create_method_step'
require '3scale_toolbox/commands/import_command/openapi/create_mapping_rule_step'
require '3scale_toolbox/commands/import_command/openapi/create_service_step'
require '3scale_toolbox/commands/import_command/openapi/create_activedocs_step'
require '3scale_toolbox/commands/import_command/openapi/update_service_proxy_step'
require '3scale_toolbox/commands/import_command/openapi/update_service_oidc_conf_step'
require '3scale_toolbox/commands/import_command/openapi/update_policies_step'
require '3scale_toolbox/commands/import_command/issuer_type_transformer'

module ThreeScaleToolbox
  module Commands
    module ImportCommand
      module OpenAPI
        class OpenAPISubcommand < Cri::CommandRunner
          include ThreeScaleToolbox::Command
          include ThreeScaleToolbox::ResourceReader

          def self.command
            Cri::Command.define do
              name        'openapi'
              usage       'openapi [opts] -d <destination> <spec> (/path/to/your/spec/file.[json|yaml|yml] OR http[s]://domain/resource/path.[json|yaml|yml])'
              summary     'Import API defintion in OpenAPI specification from a local file or URL'
              description 'Using an API definition format like OpenAPI, import to your 3scale API directly from a local OpenAPI spec compliant file or a remote URL'

              option  :d, :destination, '3scale target instance. Format: "http[s]://<authentication>@3scale_domain"', argument: :required
              option  :t, 'target_system_name', 'Target system name', argument: :required
              flag    nil, 'activedocs-hidden', 'Create ActiveDocs in hidden state'
              flag    nil, 'skip-openapi-validation', 'Skip OpenAPI schema validation'
              flag    nil, 'prefix-matching', 'Use prefix matching instead of strict matching on mapping rules derived from openapi operations'
              option  nil, 'oidc-issuer-type', 'OIDC Issuer Type (rest, keycloak)', argument: :required, transform: IssuerTypeTransformer.new            
              option  nil, 'oidc-issuer-endpoint', 'OIDC Issuer Endpoint', argument: :required
              option  nil, 'default-credentials-userkey', 'Default credentials policy userkey', argument: :required
              option  nil, 'override-private-basepath', 'Override the basepath for the private URLs', argument: :required
              option  nil, 'override-public-basepath', 'Override the basepath for the public URLs', argument: :required
              option  nil, 'staging-public-base-url', 'Custom public staging URL', argument: :required
              option  nil, 'production-public-base-url', 'Custom public production URL', argument: :required
              option  nil, 'override-private-base-url', 'Custom private base URL', argument: :required
              option nil, 'backend-api-secret-token', 'Custom secret token sent by the API gateway to the backend API',argument: :required
              option nil, 'backend-api-host-header', 'Custom host header sent by the API gateway to the backend API', argument: :required
              param   :openapi_resource

              runner OpenAPISubcommand
            end
          end

          def run
            tasks = []
            tasks << CreateServiceStep.new(context)
            # other tasks might read proxy settings (CreateActiveDocsStep does)
            tasks << UpdateServiceProxyStep.new(context)
            tasks << CreateMethodsStep.new(context)
            tasks << ThreeScaleToolbox::Commands::ServiceCommand::CopyCommand::DestroyMappingRulesTask.new(context)
            tasks << CreateMappingRulesStep.new(context)
            tasks << CreateActiveDocsStep.new(context)
            tasks << UpdateServiceOidcConfStep.new(context)
            tasks << UpdatePoliciesStep.new(context)

            # run tasks
            tasks.each(&:call)

            # This should be the last step
            ThreeScaleToolbox::Commands::ServiceCommand::CopyCommand::BumpProxyVersionTask.new(service: context[:target]).call
          end

          private

          def context
            @context ||= create_context
          end

          def create_context
            {
              api_spec_resource: openapi_resource,
              api_spec: openapi_parser,
              threescale_client: threescale_client(fetch_required_option(:destination)),
              target_system_name: options[:target_system_name],
              activedocs_published: !options[:'activedocs-hidden'],
              oidc_issuer_type: options[:'oidc-issuer-type'],
              oidc_issuer_endpoint: options[:'oidc-issuer-endpoint'],
              default_credentials_userkey: options[:'default-credentials-userkey'],
              skip_openapi_validation: options[:'skip-openapi-validation'],
              override_private_basepath: options[:'override-private-basepath'],
              override_public_basepath: options[:'override-public-basepath'],
              production_public_base_url: options[:'production-public-base-url'],
              staging_public_base_url: options[:'staging-public-base-url'],
              override_private_base_url: options[:'override-private-base-url'],
              backend_api_secret_token: options[:'backend-api-secret-token'],
              backend_api_host_header: options[:'backend-api-host-header'],
              prefix_matching: options[:'prefix-matching'],
              delete_mapping_rules: true,
            }
          end

          def openapi_resource
            @openapi_resource ||= load_resource(openapi_path)
          end

          def openapi_path
            arguments[:openapi_resource]
          end

          def validate
            !options[:'skip-openapi-validation']
          end

          def openapi_parser
            raise ThreeScaleToolbox::Error, 'only JSON/YAML format is supported' unless openapi_resource.is_a?(Hash)

            if openapi_resource.key?('openapi')
              ThreeScaleToolbox::OpenAPI::OAS3.build(openapi_path, openapi_resource, validate: validate)
            else
              ThreeScaleToolbox::OpenAPI::Swagger.build(openapi_resource, validate: validate)
            end
          rescue JSON::Schema::ValidationError => e
            raise ThreeScaleToolbox::Error, "OpenAPI schema validation failed: #{e.message}"
          end
        end
      end
    end
  end
end
