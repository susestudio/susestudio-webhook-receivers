susestudio-webhook-receivers
============================

The intent of this repository is to collect a list of reference implementations
for webhook receivers that handle notifications from SUSE Studio, both for the
hosted [online](http://susestudio.com) and
[Onsite](https://www.suse.com/products/susestudio/) versions.

Webhooks are HTTP callbacks, often used for push notifications. Using webhooks
to integrate your application or environment with SUSE Studio, one avoids the
need to keep polling for changes. Instead, SUSE Studio contacts you via [HTTP
POST](http://en.wikipedia.org/wiki/POST_%28HTTP%29) at the specified URL
whenever an event occurs, with full details in the request body so that you can
filter and process each notification accordingly. Refer to SUSE Studio's
[webhooks documentation](http://susestudio.com/docs/webhooks) for more details.

Each reference implementation in this repository (there's only one at the
moment) is described below.


webhook-receiver-SUSE_Cloud.rb
-------------------------------

This Webhook receiver is written in [Ruby](http://www.ruby-lang.org) with the
[Sinatra framework](http://www.sinatrarb.com/), both chosen for their
simplicity and conciseness.

This receiver automatically imports all new 'SUSE Cloud / OpenStack / KVM'
builds to your SUSE Cloud / OpenStack instance. It does so by listening for all
'build_finished' events that have the 'kvm' image type and importing that.
Everything else is ignored.


### Installation & Setup

Firstly, install the required Ruby dependencies:

    sudo zypper in ruby rubygem-bundler
    bundle install

You should then be able to run the script, at least to display the usage help:

    > ./webhook-receiver-SUSE_Cloud.rb --help

 Next, download the `openrc.sh` credentials file from your [SUSE
 Cloud](https://www.suse.com/products/suse-cloud/) /
 [OpenStack](http://www.openstack.org/) instance from "Settings" => "OpenStack
 Credentials" => "Download RC File".

You also need to install the glance client. The following commands are for
SLE11 SP2:

    sudo su -
    zypper addrepo \
           http://download.opensuse.org/repositories/Virtualization:/Cloud/SLE_11_SP2/ \
           Virt:Cloud
    zypper refresh Virt:Cloud
    zypper install python-glanceclient

At this point, you should test that the manual import works. You can refer to
our [blog post](http://blog.susestudio.com/2012/10/importing-images-into-suse-cloud.html)
for details on how to do that.


### Running

You must source the `openrc.sh` script (described in the previous section) and
enter the password before running the webhook receiver script, otherwise the
import to SUSE Cloud / OpenStack will fail. For example:

    > . openrc.sh
    Please enter your OpenStack Password:

Then run the receiver script from the same terminal:

    > ./webhook-receiver-SUSE_Cloud.rb

Which should produce output similar to this:

    [2012-10-08 15:37:41] INFO  WEBrick 1.3.1
    [2012-10-08 15:37:41] INFO  ruby 1.9.3 (2012-04-20) [x86_64-linux]
    == Sinatra/1.3.3 has taken the stage on 4567 for development with backup from WEBrick
    [2012-10-08 15:37:41] INFO  WEBrick::HTTPServer#start: pid=28396 port=4567

It defaults to listening on port 4567. If you are using Studio Online
(http://susestudio.com), then the host running the webhook receiver and
corresponding port must be publicly reachable. For security, you can whitelist
requests from susestudio.com (130.57.70.200) in your firewall. Similarly if you
are using Studio Onsite, the webhook receiver must be reachable by the Onsite
instance.

There are a number of command line options that you can configure (inherited
from Sinatra):

    > ./webhook-receiver-SUSE_Cloud.rb --help
    Usage: webhook-receiver-SUSE_Cloud [options]
        -p port                  set the port (default is 4567)
        -o addr                  set the host (default is 0.0.0.0)
        -e env                   set the environment (default is development)
        -s server                specify rack server/handler (default is thin)
        -x                       turn on the mutex lock (default is off)


### Logging

All requests are logged to `webhooks.log` by default. You can change this by
changing the following line in the webhook receiver script accordingly:

    env['rack.logger'] = Logger.new('webhooks.log')

Sample request log:

    I, [2012-10-05T18:32:02.545621 #4442]  INFO -- : Processing request {"payload"=>{"event"=>"build_finshed", "id"=>"24", "name"=>"My appliance", "build"=>{"id"=>"11", "version"=>"0.0.1", "image_type"=>"kvm", "image_size"=>"645", "compressed_image_size"=>"140", "download_url"=>"http://susestudio.com/download/f79d576ed150a0b877462fc0b3dcb92f/My_appliance.x86_64-0.0.1.oem.tar.gz", "md5"=>"f79d576ed150a0b877462fc0b3dcb92f"}}}

Sample log for ignored notifications (in this case, we only handle the 'kvm'
image types):

    I, [2012-10-08T13:52:40.915470 #22935]  INFO -- : Ignored image type 'oem'

Sample log for a successful import:

    I, [2012-10-08T13:58:45.587259 #23329]  INFO -- : Processing request {"payload"=>{"event"=>"build_finished", "id"=>"24", "name"=>"Webhooks Test", "build"=>{"id"=>"11", "version"=>"0.0.1", "image_type"=>"kvm", "image_size"=>"645", "compressed_image_size"=>"140", "download_url"=>"http://bit.ly/UHn5C7", "md5"=>"f79d576ed150a0b877462fc0b3dcb92f"}}}
    I, [2012-10-08T13:58:45.587685 #23329]  INFO -- : Running command:  glance --insecure image-create --name="Webhooks Test" --is-public=True --disk-format=qcow2 --container-format=bare --copy-from "http://bit.ly/UHn5C7" 2>&1
    I, [2012-10-08T13:58:46.933713 #23329]  INFO -- : Output:
    +------------------+--------------------------------------+
    | Property         | Value                                |
    +------------------+--------------------------------------+
    | checksum         | 60f88f23a860a4fa05978209072ae64d     |
    | container_format | bare                                 |
    | created_at       | 2012-10-08T14:00:34.663139           |
    | deleted          | False                                |
    | deleted_at       | None                                 |
    | disk_format      | qcow2                                |
    | id               | 260d3d89-c00f-4f3d-9e03-353544809a3d |
    | is_public        | True                                 |
    | min_disk         | 0                                    |
    | min_ram          | 0                                    |
    | name             | Webhooks Test                        |
    | owner            | 25c05b2282c84622bc9a0db422664c96     |
    | protected        | False                                |
    | size             | 188                                  |
    | status           | active                               |
    | updated_at       | 2012-10-08T14:00:35.209841           |
    +------------------+--------------------------------------+

    I, [2012-10-08T13:58:46.933881 #23329]  INFO -- : Import succeeded


### Testing

You can mimic a webhook notification from Studio by running the following in
the command line (change the values as needed):

    curl -i -X POST \
      -d 'payload[event]=build_finished' \
      -d 'payload[id]=24' \
      -d 'payload[name]=Webhooks Test' \
      -d 'payload[build][id]=11' \
      -d 'payload[build][version]=0.0.1' \
      -d 'payload[build][image_type]=kvm' \
      -d 'payload[build][image_size]=645' \
      -d 'payload[build][compressed_image_size]=140' \
      -d 'payload[build][download_url]=http://bit.ly/UHn5C7' \
      -d 'payload[build][md5]=f79d576ed150a0b877462fc0b3dcb92f' \
      'http://localhost:4567/'


### Feedback, bug reports, and contributions

Please send your feedback and bug reports to feedback@susestudio.com. Pull
requests are very much welcomed.
