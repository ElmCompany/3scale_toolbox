RSpec.describe ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::OpenAPISubcommand do
  include_context :temp_dir
  include_context :resources

  let(:arguments) { { 'openapi_resource': oas_resource } }
  let(:options) { { 'destination': 'https://destination_key@destination.example.com' } }
  subject { described_class.new(options, arguments, nil) }

  context 'valid openapi content' do
    let(:oas_resource) { File.join(resources_path, 'valid_swagger.yaml') }

    context '#run' do
      before :each do
        expect(subject).to receive(:threescale_client)
      end

      it 'all required tasks are run' do
        # Task stubs
        [
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::CreateServiceStep,
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::UpdateServiceProxyStep,
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::CreateMethodsStep,
          ThreeScaleToolbox::Commands::ServiceCommand::CopyCommand::DestroyMappingRulesTask,
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::CreateMappingRulesStep,
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::CreateActiveDocsStep,
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::UpdateServiceOidcConfStep,
          ThreeScaleToolbox::Commands::ImportCommand::OpenAPI::UpdatePoliciesStep,
          ThreeScaleToolbox::Commands::ServiceCommand::CopyCommand::BumpProxyVersionTask,
        ].each do |task_class|
          task = instance_double(task_class.to_s)
          task_class_obj = class_double(task_class).as_stubbed_const
          expect(task_class_obj).to receive(:new).and_return(task)
          expect(task).to receive(:call)
        end

        # Run
        subject.run
      end
    end
  end

  context 'invalid openapi content' do
    let(:oas_content) do
      <<~YAML
        ---
        swagger: "2.0"
        info:
          desSSSSScription: "Invalid description tag"
      YAML
    end
    let(:oas_resource) { tmp_dir.join('invalid.yaml').tap { |conf| conf.write(oas_content) } }

    context '#run' do
      it 'raises error' do
        expect { subject.run }.to raise_error(ThreeScaleToolbox::Error,
                                              /OpenAPI schema validation failed/)
      end
    end
  end

  context 'invalid html openapi content' do
    let(:oas_content) do
      <<~EOF
        <!DOCTYPE html>
        <html>
          <body>
            <h1>My First Heading</h1>
            <p>My first paragraph.</p>
          </body>
        </html>
      EOF
    end
    let(:oas_resource) { tmp_dir.join('invalid.yaml').tap { |conf| conf.write(oas_content) } }

    context '#run' do
      it 'raises error' do
        expect { subject.run }.to raise_error(ThreeScaleToolbox::Error,
                                              /only JSON\/YAML format is supported/)
      end
    end
  end
end
