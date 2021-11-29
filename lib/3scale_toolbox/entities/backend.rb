module ThreeScaleToolbox
  module Entities
    class Backend
      include CRD::BackendSerializer

      VALID_PARAMS = %w[name description system_name private_endpoint].freeze
      public_constant :VALID_PARAMS

      VALID_UPDATE_PARAMS = %w[name description private_endpoint].freeze
      public_constant :VALID_PARAMS

      class << self
        def create(remote:, attrs:)
          b_attrs = remote.create_backend Helper.filter_params(VALID_PARAMS, attrs)
          if (errors = b_attrs['errors'])
            raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend has not been created', errors)
          end

          new(id: b_attrs.fetch('id'), remote: remote, attrs: b_attrs)
        end

        # ref can be system_name or backend_id
        def find(remote:, ref:)
          new(id: ref, remote: remote).tap(&:attrs)
        rescue ThreeScaleToolbox::InvalidIdError, ThreeScale::API::HttpClient::NotFoundError
          find_by_system_name(remote: remote, system_name: ref)
        end

        def find_by_system_name(remote:, system_name:)
          attrs = list_backends(remote: remote).find do |backend|
            backend['system_name'] == system_name
          end
          return if attrs.nil?

          new(id: attrs.fetch('id'), remote: remote, attrs: attrs)
        end

        private

        def list_backends(remote:)
          backends_enum(remote: remote).reduce([], :concat)
        end

        def backends_enum(remote:)
          Enumerator.new do |yielder|
            page = 1
            loop do
              list = remote.list_backends(
                page: page,
                per_page: ThreeScale::API::MAX_BACKENDS_PER_PAGE
              )

              if list.respond_to?(:has_key?) && (errors = list['errors'])
                raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend list not read', errors)
              end

              break if list.nil?

              yielder << list

              # The API response does not tell how many pages there are available
              # If one page is not fully filled, it means that it is the last page.
              break if list.length < ThreeScale::API::MAX_BACKENDS_PER_PAGE

              page += 1
            end
          end
        end
      end

      attr_reader :id, :remote

      def initialize(id:, remote:, attrs: nil)
        @id = id.to_i
        @remote = remote
        @attrs = attrs
      end

      def attrs
        @attrs ||= fetch_backend_attrs
      end

      def system_name
        attrs['system_name']
      end

      def description
        attrs['description']
      end

      def name
        attrs['name']
      end

      def private_endpoint
        attrs['private_endpoint']
      end

      def metrics
        metric_attr_list = metrics_and_methods.select { |metric_attrs| metric_attrs['parent_id'].nil? }

        metric_attr_list.map do |metric_attrs|
          BackendMetric.new(id: metric_attrs.fetch('id'), backend: self, attrs: metric_attrs)
        end
      end

      def hits
        metric_list = metrics_and_methods.map do |metric_attrs|
          BackendMetric.new(id: metric_attrs.fetch('id'), backend: self, attrs: metric_attrs)
        end
        metric_list.find { |metric| metric.system_name == 'hits' }.tap do |hits_metric|
          raise ThreeScaleToolbox::Error, 'missing hits metric' if hits_metric.nil?
        end
      end

      # @api public
      # @return [List]
      def methods
        method_attr_list = remote.list_backend_methods id, hits.id
        if method_attr_list.respond_to?(:has_key?) && (errors = method_attr_list['errors'])
          raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend methods not read', errors)
        end

        method_attr_list.map do |method_attrs|
          BackendMethod.new(id: method_attrs.fetch('id'), backend: self, attrs: method_attrs)
        end
      end

      def mapping_rules
        m_r = remote.list_backend_mapping_rules id
        if m_r.respond_to?(:has_key?) && (errors = m_r['errors'])
          raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend mapping rules not read', errors)
        end

        m_r.map do |mr_attrs|
          BackendMappingRule.new(id: mr_attrs.fetch('id'), backend: self, attrs: mr_attrs)
        end
      end

      def update(b_attrs)
        # Only update different attrs
        update_attrs = VALID_UPDATE_PARAMS.each_with_object({}) do |key, target|
          target[key] = b_attrs.fetch(key) unless attrs[key].nil? || attrs.fetch(key) == b_attrs[key]
        end

        return attrs if update_attrs.empty?

        new_attrs = remote.update_backend id, update_attrs
        if (errors = new_attrs['errors'])
          raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend not updated', errors)
        end

        # update current attrs
        @attrs = new_attrs

        new_attrs
      end

      def delete
        remote.delete_backend id
      end

      # Compute matrics mapping
      def metrics_mapping(other)
        (metrics + methods).product(other.metrics + other.methods).select do |m_a, m_b|
          m_a.system_name == m_b.system_name
        end.map { |m_a, m_b| [m_a.id, m_b.id] }.to_h
      end

      def ==(other)
        remote.http_client.endpoint == other.remote.http_client.endpoint && id == other.id
      end

      def find_metric_or_method(system_name)
        (metrics + methods).find { |m| m.system_name == system_name }
      end

      private

      def metrics_and_methods
        m_m = remote.list_backend_metrics id
        if m_m.respond_to?(:has_key?) && (errors = m_m['errors'])
          raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend metrics not read', errors)
        end

        m_m
      end

      def fetch_backend_attrs
        raise ThreeScaleToolbox::InvalidIdError if id.zero?

        backend = remote.backend id
        if (errors = backend['errors'])
          raise ThreeScaleToolbox::ThreeScaleApiError.new('Backend attrs not read', errors)
        end

        backend
      end
    end
  end
end
