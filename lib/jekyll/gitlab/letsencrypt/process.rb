require 'faraday'

module Jekyll
  module Gitlab
    module Letsencrypt
      class Process

        attr_accessor :client

        def self.process!
          client = Acme.new.register!
          self.new(client).process!
        end

        delegate :base_path, :gitlab_repo, :pretty_url?, :layout, :domain, :initial_delay, :delay_time, to: Configuration

        def initialize(client)
          @client = client
        end

        def process!
          Jekyll.logger.abort_with "Client is already authorized." if client.authorized?

          commit_to_gitlab!
          wait_until_challenge_is_present
          request_verification!
          await_verification_confirmation
          display_certificate
        end

      private

        def commit_to_gitlab!
          Jekyll.logger.info "Pushing file to Gitlab"
          Commiter.new(challenge_content).commit!
        end

        def wait_until_challenge_is_present
          Jekyll.logger.info "Going to check #{challenge_url} for the challenge to be present..."
          Jekyll.logger.info "Waiting #{initial_delay} seconds before we start checking for challenge.."
          sleep initial_delay

          loop do
            response = Faraday.get challenge_url
            if response.success?
              Jekyll.logger.info "Got response code #{response.status}, file is present!"
              return
            end
            Jekyll.logger.info "Got response code #{response.status}, waiting #{delay_time} seconds..."
            sleep delay_time
          end
        end

        def request_verification!
          Jekyll.logger.info "Requesting verification..."
          challenge.request_verification
        end

        def await_verification_confirmation
          tries = 0
          loop do
            tries = tries + 1
            if challenge.authorization.verify_status == 'valid'
              Jekyll.logger.info "Challenge is valid!"
              return
            end
            Jekyll.logger.info "Challenge status = #{challenge.authorization.verify_status}"
            Jekyll.logger.abort_with "Challenge failed to verify" if tries >= 3
            sleep delay_time
          end
        end

        def display_certificate
          Jekyll.logger.info "Certifcate retrieved!"
          Jekyll.logger.info "Go to https://gitlab.com/#{gitlab_repo}/pages"
          Jekyll.logger.info " - If you already have an existing entry for #{domain}, remove it"
          Jekyll.logger.info " - Then click + New Domain and enter the following:"
          Jekyll.logger.info ""
          Jekyll.logger.info "Domain: #{domain}"
          Jekyll.logger.info ""
          Jekyll.logger.info "Certificate (PEM): "
          Jekyll.logger.info certificate.fullchain_to_pem
          Jekyll.logger.info "\n"
          Jekyll.logger.info "Key (PEM): "
          Jekyll.logger.info certificate.request.private_key.to_pem
          Jekyll.logger.info ""
          Jekyll.logger.info ""
          Jekyll.logger.info "... hit save, wait a bit, and your new SSL will be live!"
        end

        def challenge_content
          permalink  = ""
          permalink += base_path if base_path
          permalink += challenge.filename
          permalink += "/" if pretty_url?

          content  = "---\n"
          content += "layout: #{layout}\n"
          content += "permalink: #{permalink}\n"
          content += "---\n"
          content += "\n"
          content += challenge.file_content
          content += "\n"

          content
        end

        def challenge_url
          @challenge_url ||= begin
            url  = "http://#{domain}/"
            url += challenge.filename
            url += "/" if pretty_url?
            url
          end
        end

        def challenge
          @challenge ||= client.challenge
        end

        def certificate
          @certificate ||= begin
            csr = ::Acme::Client::CertificateRequest.new names: Array(domain)
            client.client.new_certificate csr
          end
        end
      end
    end
  end
end
