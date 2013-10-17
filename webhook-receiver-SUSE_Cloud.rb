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

before do
  env['rack.logger'] = Logger.new('/var/log/susestudio-webhook-receiver.log')
end

helpers do
  def import_image(name, url, version, format)
    case format
      when "kvm"
        disk_format = "qcow2"
        source = "--copy-from \"#{url}\""
        properties = "--property hypervisor_type=kvm"

      when "xen"
        disk_format= "raw"
        filename = url.split('/').last
        command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
          curl -L #{url} | tar -xz -C /tmp/ 2>&1
        EOS
        logger.info "Running command: #{command}"
        output = `#{command}`
        logger.info "Output:\n#{output}"
        if $?.success?
          logger.info "Xen raw image extraction succeeded"
        else
          logger.error "Xen raw image extraction failed"
        end
        source = "< /tmp/#{filename.split('.').first}-#{version}/#{filename.split('.').first}.#{filename.split('.')[1].split('-').first}-#{version}.raw"
        properties = "--property hypervisor_type=xen --property vm_mode=xen"

      when "vmx"
        disk_format = "vmdk"
        filename = url.split('/').last
        command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
          curl -L #{url} | tar -xz -C /tmp/ 2>&1
        EOS
        logger.info "Running command: #{command}"
        output = `#{command}`
        logger.info "Output:\n#{output}"
        if $?.success?
          logger.info "vmdk image extraction succeeded"
        else
          logger.error "vmdk image extraction failed"
        end

        basefile = "/tmp/#{filename.split('.').first}-#{version}/#{filename.split('.').first}.#{filename.split('.')[1].split('-').first}-#{version}"

        command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
          /usr/bin/vmware-vdiskmanager -r #{basefile}.vmdk -t 4 #{basefile}-conv.vmdk
        EOS
        logger.info "Running command: #{command}"
        output = `#{command}`
        logger.info "Output:\n#{output}"
        if $?.success?
          logger.info "Conversion for ESXi succeeded"
        else
          logger.error "Conversion for ESXi failed"
        end
        source = "< #{basefile}-conv-flat.vmdk"
        properties = "--property hypervisor_type=vmware --property vmware_adaptertype=lsiLogic --property vmware_disktype=preallocated"

      else
        logger.error "Invalid format for import_image function"
    end
    task = Thread.new do
      case format
        when "kvm", "xen", "vmx"
          command = <<-EOS.gsub(/^\s+/, ' ').gsub(/\n/, '')
            glance image-create
                 --name="#{name}-#{version}-#{format}" --is-public=True --disk-format=#{disk_format}
                 --container-format=bare #{properties} #{source}  2>&1
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
      case format
        when "xen", "vmx"
          FileUtils.remove_dir("/tmp/#{name.gsub(/ /, "_")}-#{version}", force=true)
          if $?.success?
            logger.info "Temporary file delete succeeded"
          else
            logger.error "Temporary file delete failed"
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
  logger.info "#{payload}"
  event = payload["event"]
  die "Missing '[payload][event]'" if event.nil?

  if event == 'build_finished'
    image_type = payload["build"]["image_type"]
    die "Missing '[payload][build][image_type]" if image_type.nil?

    case image_type
      when 'kvm', 'xen', 'vmx'
        name = payload["name"]
        url = payload["build"]["download_url"]
        version = payload["build"]["version"]
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
