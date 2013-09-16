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

set :bind, '0.0.0.0'
set :port, 4567

#before do
#  env['rack.logger'] = Logger.new('webhooks.log')
#end

helpers do
  def import_image(name, url, version, format)
    if format == "kvm"
      disk_format = "qcow2"
      source = "--copy-from \"#{url}\""
    elsif format == "xen"
      disk_format= "raw"
      filename = url.split('/').last
      command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
        curl -L #{url} | tar -xz -C /tmp/ 2>&1
      EOS
      logger.info "Running command: #{command}"
      output = `#{command}`
      logger.info "Output:\n#{output}"
#      if 0.success?
#        logger.info "Xen raw image extraction succeeded"
#      else
#        logger.error "Xen raw image extraction failed"
#      end
      source = "< /tmp/#{filename.split('.').first}-#{version}/#{filename.split('.').first}.#{filename.split('.')[1].split('-').first}-#{version}.raw"
    else
      logger.error "Invalid format for import_image function"
    end
    task = Thread.new do
      command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
        glance image-create
               --name="#{name}-#{version}-#{format}" --is-public=True --disk-format=#{disk_format}
               --container-format=bare --property hypervisor_type=#{format} #{source}  2>&1
      EOS
      logger.info "Running command: #{command}"
      output = `#{command}`
      logger.info "Output:\n#{output}"
      if 0.success?
        logger.info "Import succeeded"
      else
        logger.error "Import failed"
      end
      if format == "xen"
        command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
          rm -Rf /tmp/#{name}-#{version}
        EOS
        logger.info "Running command: #{command}"
        output = `#{command}`
        logger.info "Output:\n#{output}"
        if 0.success?
          logger.info "Xen temporary file delete succeeded"
        else
          logger.error "Xen temporary file delete failed"
        end
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

    if image_type == 'kvm' || image_type == 'xen'
      name = payload["name"]
      url  = payload["build"]["download_url"]
      version  = payload["build"]["version"]
      die "Missing '[payload][name]'" if name.nil?
      die "Missing '[payload][version]'" if version.nil?
      die "Missing '[payload][build][download_url]'" if url.nil?

      import_image(name, url, version, image_type)
    else
      skip "Ignored image type '#{image_type}'"
    end
  else
    skip "Ignored event type '#{event}'"
  end
end
