require_relative 'meta_api/client'
require 'promostandards/client/version'
require 'promostandards/client/no_service_url_error'
require 'savon'
require 'promostandards/primary_image_extractor'

module PromoStandards
  class Client
    COMMON_SAVON_CLIENT_CONFIG = {
      # pretty_print_xml: true,
      # log: true,
      env_namespace: :soapenv,
      namespace_identifier: :ns
    }

    PRIMARY_IMAGE_PRECEDENCE = ['1006', ['1007', '1001', '2001'], ['1007', '1001'], '1007', ['1001', '2001'], '1001', '1003']

    def initialize(access_id:, password: nil, product_data_service_url:, media_content_service_url: nil, product_pricing_and_configuration_service_url: nil, inventory_service_url: nil)
      @access_id = access_id
      @password = password
      @product_data_service_url = product_data_service_url
      @media_content_service_url = media_content_service_url
      @product_pricing_and_configuration_service_url = product_pricing_and_configuration_service_url
      @inventory_service_url = inventory_service_url
    end

    def get_sellable_product_ids(version = '')
      client = build_savon_client_for_product(@product_data_service_url)
      version = version == '2.0.0' || version == '1.0.0' ? version : '2.0.0';
      response = client.call('GetProductSellableRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:isSellable' => true
        },
        soap_action: 'getProductSellable'
      )
      response
        .body[:get_product_sellable_response][:product_sellable_array][:product_sellable]
        .map { |product_data| product_data[:product_id] }
        .uniq
    end

    def get_inventory_levels(product_id, version = '')
      raise Promostandards::Client::NoServiceUrlError, 'Inventory service URL not set!' unless @inventory_service_url
      client = build_savon_client_for_inventory(@inventory_service_url)
      version = version == '2.0.0' || version == '1.2.1' ? version : '2.0.0';
      response = client.call('GetFilterValuesRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:productId' => product_id
        },
        soap_action: 'getFilterValues'
      )
      filter_hash = response.body.dig(:get_inventory_levels_response, :filter_values, :filter)
      result = client.call('GetInventoryLevelsRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:productId' => product_id,
          'shar:filter' => filter_hash
        },
        soap_action: 'getInventoryLevels'
      )
      inventory_hash = result.body.dig(:get_inventory_levels_response, :inventory, :part_inventory_array, :part_inventory)
      inventory_hash
    rescue => exception
      raise exception.class, "#{exception} - get_inventory_levels failed!"
    end

    def get_product_data(product_id, version = '')
      client = build_savon_client_for_product(@product_data_service_url)
      version = version == '2.0.0' || version == '1.0.0' ? version : '2.0.0';
      response = client.call('GetProductRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:localizationCountry' => 'US',
          'shar:localizationLanguage' => 'en',
          'shar:productId' => product_id
        },
        soap_action: 'getProduct'
      )
      product_hash = response.body[:get_product_response][:product]
      if(product_hash[:description]).is_a? Array
        product_hash[:description] = product_hash[:description].join('\n')
      end
      product_hash
    rescue => exception
      raise exception.class, "#{exception} - get_product_data failed!"
    end

    def get_primary_image(product_id, version = '')
      raise Promostandards::Client::NoServiceUrlError, 'Media content service URL not set!' unless @media_content_service_url
      client = build_savon_client_for_media(@media_content_service_url)
      version = version == '1.1.0' ? version : '1.1.0';
      response = client.call('GetMediaContentRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:mediaType' => 'Image',
          'shar:productId' => product_id,
        },
        soap_action: 'getMediaContent'
      )

      media_content = response.body.dig(:get_media_content_response, :media_content_array, :media_content)

      PrimaryImageExtractor.new.extract(media_content)
    rescue => exception
      raise exception.class, "#{exception} - get_primary_image failed!"
    end

    def get_fob_points(product_id, version = '')
      raise Promostandards::Client::NoServiceUrlError, 'Product pricing and configuration service URL not set!' unless @product_pricing_and_configuration_service_url
      client = build_savon_client_for_product_pricing_and_configuration(@product_pricing_and_configuration_service_url)
      version = version == '1.0.0' ? version : '1.0.0';
      response = client.call('GetFobPointsRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:productId' => product_id,
          'shar:localizationCountry' => 'US',
          'shar:localizationLanguage' => 'en',
        },
        soap_action: 'getFobPoints'
      )

      fob_points_hash = response.body.dig(:get_fob_points_response, :fob_point_array, :fob_point)

      fob_points_hash
    rescue => exception
      raise exception.class, "#{exception} - get_fob_points failed!"
    end

    def get_prices(product_id, fob_id, configuration_type = 'Decorated', version = '')
      raise Promostandards::Client::NoServiceUrlError, 'Product pricing and configuration service URL not set!' unless @product_pricing_and_configuration_service_url
      client = build_savon_client_for_product_pricing_and_configuration(@product_pricing_and_configuration_service_url)
      version = version == '1.0.0' ? version : '1.0.0';
      response = client.call('GetConfigurationAndPricingRequest',
        message: {
          'shar:wsVersion' => version,
          'shar:id' => @access_id,
          'shar:password' => @password,
          'shar:productId' => product_id,
          'shar:currency' => 'USD',
          'shar:fobId' => fob_id,
          'shar:priceType' => 'List',
          'shar:localizationCountry' => 'US',
          'shar:localizationLanguage' => 'en',
          'shar:configurationType' => configuration_type,
        },
        soap_action: 'getConfigurationAndPricing'
      )

      if configuration_type == 'Decorated' && response.body.dig(:get_configuration_and_pricing_response, :error_message, :code) == '406'
        get_prices(product_id, fob_id, 'Blank')
      else
        response.body.dig(:get_configuration_and_pricing_response, :configuration, :part_array, :part)
      end
    rescue => exception
      raise exception.class, "#{exception} - get_prices failed!"
    end

    private

    def build_savon_client_for_product(service_url)
      Savon.client COMMON_SAVON_CLIENT_CONFIG.merge(
        endpoint: service_url,
        namespace: 'http://www.promostandards.org/WSDL/ProductDataService/1.0.0/',
        namespaces: {
          'xmlns:shar' => 'http://www.promostandards.org/WSDL/ProductDataService/1.0.0/SharedObjects/'
        }
      )
    end

    def build_savon_client_for_inventory(service_url)
      Savon.client COMMON_SAVON_CLIENT_CONFIG.merge(
        endpoint: service_url,
        namespace: 'http://www.promostandards.org/WSDL/Inventory/2.0.0/',
        namespaces: {
          'xmlns:shar' => 'http://www.promostandards.org/WSDL/Inventory/2.0.0/SharedObjects/'
        }
      )
    end

    def build_savon_client_for_media(service_url)
      Savon.client COMMON_SAVON_CLIENT_CONFIG.merge(
        endpoint: service_url,
        namespace: 'http://www.promostandards.org/WSDL/MediaService/1.0.0/',
        namespaces: {
          'xmlns:shar' => 'http://www.promostandards.org/WSDL/MediaService/1.0.0/SharedObjects/'
        }
      )
    end

    def build_savon_client_for_product_pricing_and_configuration(service_url)
      Savon.client COMMON_SAVON_CLIENT_CONFIG.merge(
        endpoint: service_url,
        namespace: 'http://www.promostandards.org/WSDL/PricingAndConfiguration/1.0.0/',
        namespaces: {
          'xmlns:shar' => 'http://www.promostandards.org/WSDL/PricingAndConfiguration/1.0.0/SharedObjects/'
        }
      )
    end
  end
end