#require 'net/http'
require 'rest-client'

module ActivePublicResources
  module Drivers
    class Curiosity < Driver

      DRIVER_NAME="curiosity"

      def initialize(config_options={})
        validate_options(config_options,
          [:api_key, :api_client])

        @api_key = config_options[:api_key]
        @api_client = config_options[:api_client]

      end

      def perform_request(request_criteria)
        request_criteria.validate_presence!([:query])
        api_root = 'https://api.curiosity.com/api_v2/memes/search/' << request_criteria.query
        uri = URI(api_root)
        params = {
          'fields' => '*',
          #'orderby' => normalize_request_criteria(request_criteria, 'sort') || '-view_count',
          'offset' => offset(request_criteria.page, request_criteria.per_page),
          'limit' => request_criteria.per_page || 25
        }
        uri.query = URI.encode_www_form(params)


        headers = {
            'X-Curiosity-Access-Token' => @api_key,
            'X-Curiosity-Client' => @api_client
        }

        res = RestClient::Request.execute(
            :method => :get,
            :url => uri.to_s,
            :headers => headers
        )
        results = JSON.parse(res)

        return parse_results(request_criteria, results)
      end

    private

      def offset(page, per_page)
        p = page || 1
        pp = per_page || 20
        p * pp - pp
      end

      def normalize_request_criteria(request_criteria, field_name)
        case field_name
          when 'sort'
            case request_criteria.instance_variable_get("@#{field_name}")
              when 'views'
                return '-view_count'
              else
                return '-view_count'
            end
          else
            request_criteria.instance_variable_get("@#{field_name}")
        end
      end

      def parse_results(request_criteria, results)
        @driver_response = DriverResponse.new(
          :criteria      => request_criteria,
          :next_criteria => next_criteria(request_criteria, results),
          :total_items   => results['meta']['total_count'],
          :items         => results['objects'].map { |data| parse_video(data) }
        )
      end

      def next_criteria(request_criteria, results)
        if results['meta']['has_next']
          return RequestCriteria.new({
            :query    => request_criteria.query,
            :page     => (request_criteria.page || 1) + 1,
            :per_page => results['meta']['limit'].to_i
          })
        end
      end

      def parse_video(data)
        img = data['thumbor_meme_image'].gsub('\(', '(').gsub('\)', ')')

        video = ActivePublicResources::ResponseTypes::Video.new
        video.id            = data['id']
        video.title         = data['title']
        video.description   = data['notes']
        video.thumbnail_url = img
        video.url           = "https://curiosity.com/memes/#{data['slug']}/?ref=canvas"
        video.embed_url     = "https://m.curiosity.com/memes/#{data['slug']}/?ref=canvas"
        video.duration      = 0
        video.num_views     = 0
        video.num_likes     = 0
        video.num_comments  = 0
        video.created_date = Time.at(data['__created__']['utc_ms'] / 1000)
        video.username      = 'Curiosity'
        video.width         = 600
        video.height        = 600

        # Return Types
        video.return_types << APR::ReturnTypes::Url.new(
          :driver => DRIVER_NAME,
          :remote_id => video.id,
          :url   => video.url,
          :text  => video.description,
          :title => video.title
        )
        video.return_types << APR::ReturnTypes::Iframe.new(
          :driver => DRIVER_NAME,
          :remote_id => video.id,
          :url    => video.embed_url,
          :text   => video.description,
          :title  => video.title,
          :width  => 968,
          :height => 560 
        )

        video
      end

    end
  end
end
