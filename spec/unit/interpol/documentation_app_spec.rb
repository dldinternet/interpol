require 'fast_spec_helper'
require 'interpol/documentation_app'
require 'rack/test'

module Interpol
  describe DocumentationApp do
    include Rack::Test::Methods

    let_without_indentation(:endpoint_definition_yml) do <<-EOF
      ---
      name: project_list
      route: /users/:user_id/projects
      method: GET
      definitions:
        - versions: ["1.0"]
          schema:
            type: object
            properties:
              name:
                type: string
          examples:
            - name: "some project"
      EOF
    end


    let(:endpoint) { Endpoint.new(YAML.load endpoint_definition_yml) }
    attr_accessor :skip_doc_title_config

    let(:app) do
      skip_doc_title_config = self.skip_doc_title_config
      DocumentationApp.build do |config|
        config.endpoints = [endpoint]
        config.documentation_title = "My Cool API" unless skip_doc_title_config
      end.tap do |a|
        a.use Rack::Lint
        a.set :raise_errors, true
        a.set :show_exceptions, false
      end
    end

    it 'has a name since some tools except all classes to have a name' do
      expect(app).to be_a(Class)
      expect(app.name).to include("Interpol", "DocumentationApp", "anon")
    end

    it 'renders documentation' do
      get '/'
      expect(last_response.body).to include("project_list", "/users/:user_id/projects")
    end

    it 'includes the configured documentation_title in the markup' do
      get '/'
      expect(last_response.body).to include("My Cool API")
    end

    it 'provides a default title when none is configured' do
      self.skip_doc_title_config = true
      get '/'
      expect(last_response.body).to include("API Documentation Provided by Interpol")
    end

    describe ".render_static_page" do
      let(:public_folder) { DocumentationApp.build.public_folder }

      def first_line_of(name)
        File.read(File.join(public_folder, name)).split("\n").first.strip
      end

      let(:static_page) do
        DocumentationApp.render_static_page do |config|
          config.endpoints = [endpoint]
          config.documentation_title = "My Cool API"
        end
      end

      let(:doc) { Nokogiri::HTML(static_page) }

      it "renders the documentation with inlined stylesheets and javascript" do
        expect(static_page).to include("project_list", "My Cool API")

        expect(doc.css("link[rel=stylesheet]").size).to eq(0)
        expect(static_page).to include(first_line_of "stylesheets/screen.css")

        expect(doc.css("script[src]").size).to eq(0)
        expect(static_page).to include(first_line_of "javascripts/interpol.js")
      end
    end
  end
end

