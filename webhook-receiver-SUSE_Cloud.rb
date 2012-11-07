#!/usr/bin/ruby
#
# Simple Sinatra (http://www.sinatrarb.com) script that handles Webhooks
# notification from SUSE Studio (both Online and Onsite versions).
#
# Listens for 'build_finished' notifications with the 'kvm' image type, and
# automatically imports it to your SUSE Cloud or OpenStack instance.
#
# See README.md for details.
#
# Author: James Tan <jatan@suse.com>

require 'rubygems'
require 'sinatra'
require 'json'

configure do
  enable :logging
end

before do
  env['rack.logger'] = Logger.new('webhooks.log')
end

helpers do
  def import_image(name, url)
    task = Thread.new do
      command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
        glance image-create
               --name="#{name}" --is-public=True --disk-format=qcow2
               --container-format=bare --copy-from "#{url}" 2>&1
      EOS
      logger.info "Running command: #{command}"
      output = `#{command}`
      logger.info "Output:\n#{output}"
      if $?.success?
        logger.info "Import succeeded"
      else
        logger.error "Import failed"
      end
    end
  end

  def die(message)
    logger.error "Bad request (400): #{message}"
    halt 400, "Error: #{message}\n"
  end

  def skip(message)
    logger.info "#{message}"
    halt "#{message}\n"
  end
end

post '/' do
  logger.info "Processing request #{params.inspect}"

  payload = JSON.parse(params["payload"])
  event   = payload["event"]
  die "Missing '[payload][event]'" if event.nil?

  if event == 'build_finished'
    image_type = payload["build"]["image_type"]
    die "Missing '[payload][build][image_type]" if image_type.nil?

    if image_type == 'kvm'
      name = payload["name"]
      url  = payload["build"]["download_url"]
      die "Missing '[payload][name]'" if name.nil?
      die "Missing '[payload][build][download_url]'" if url.nil?

      import_image(name, url)
    else
      skip "Ignored image type '#{image_type}'"
    end
  else
    skip "Ignored event type '#{event}'"
  end
end
