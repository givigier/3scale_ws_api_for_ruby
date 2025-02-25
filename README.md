# Rubygem for 3scale Web Service Management API


[<img src="https://secure.travis-ci.org/3scale/3scale_ws_api_for_ruby.png?branch=master" alt="Build Status" />](http://travis-ci.org/3scale/3scale_ws_api_for_ruby)

3scale is an API Infrastructure service which handles API Keys, Rate Limiting, Analytics, Billing Payments and Developer Management. Includes a configurable API dashboard and developer portal CMS. More product stuff at http://www.3scale.net/, support information at http://support.3scale.net/.

### Tutorials
Plugin Setup: https://support.3scale.net/howtos/api-configuration/plugin-setup
Rate Limiting: https://support.3scale.net/howtos/basics/provision-rate-limits
Analytics Setup: https://support.3scale.net/quickstarts/3scale-api-analytics

## Installation

This library is distributed as a gem:
```sh
gem install 3scale_client
```
Or alternatively, download the source code from github:
http://github.com/3scale/3scale_ws_api_for_ruby

If you are using Bundler, please add this to your Gemfile:

```ruby
gem '3scale_client'
```
and do a bundle install.

If you are using Rails' config.gems, put this into your config/environment.rb

```ruby
config.gem '3scale_client'
```
Otherwise, require the gem in whatever way is natural to your framework of choice.

## Usage

First, create an instance of the client, giving it your provider API key:

```ruby
client = ThreeScale::Client.new(:provider_key => "your provider key")
```
Because the object is stateless, you can create just one and store it globally.


### SSL and Persistence

Starting with version 2.4.0 you can use two more options: `:secure` and `:persistent` like:

```ruby
client = ThreeScale::Client.new(:provider_key => '...', :secure => true, :persistent => true)
```

#### :secure

Enabling secure will force all traffic going through HTTPS.
Because estabilishing SSL/TLS for every call is expensive, there is `:persistent`.

#### :persistent

Enabling persistent will use HTTP Keep-Alive to keep open connection to our servers.
This option requires installing gem `net-http-persistent`.

### Authrep

Authrep is a 'one-shot' operation to authorize an application and report the associated transaction at the same time.
The main difference between this call and the regular authorize call is that usage will be reported if the authorization is successful. Read more about authrep at the [active docs page on the 3scale's support site](https://support.3scale.net/reference/activedocs#operation/66)

You can make request to this backend operation like this:

```ruby
response = client.authrep(:app_id => "the app id", :app_key => "the app key")
```

Then call the +success?+ method on the returned object to see if the authorization was
successful.

```ruby
if response.success?
  # All fine, the usage will be reported automatically. Proceeed.
else
  # Something's wrong with this application.
end
```

The example is using the app_id authentication pattern, but you can also use other patterns.

#### A rails example


```ruby
class ApplicationController < ActionController
  # Call the authenticate method on each request to the API
  before_filter :authenticate
        
  # You only need to instantiate a new Client once and store it as a global variable
  # You should store your provider key in the environment because this key is secret!
  def create_client
    @@threescale_client ||= ThreeScale::Client.new(:provider_key => ENV['PROVIDER_KEY'])    
  end
        
  # To record usage, create a new metric in your application plan. You will use the 
  # "system name" that you specifed on the metric/method to pass in as the key to the usage hash. 
  # The key needs to be a symbol. 
  # A way to pass the metric is to add a parameter that will pass the name of the metric/method along
  def authenticate
    response = create_client.authrep(:app_id => params["app_id"], 
                                     :app_key => params["app_key"],
                                     :usage => { params[:metric].to_sym => 1 }
    if response.success?
      return true
      # All fine, the usage will be reported automatically. Proceeed.
    else
      # Something's wrong with this application.
      puts "#{response.error_message}"
      # raise error
    end
  end
end
```

### Using Varnish to speed up things

3scale provides a [varnish module](https://github.com/3scale/libvmod-3scale) to cache the responses of its backend to help you achieve a close to zero latency. Go and install the module and [configure it the easy way](https://github.com/3scale/libvmod-3scale/blob/master/vcl/default_3scale_simple.vcl)

When that's done all you have to do is to initialize your 3scale client pointing to the location of your varnish, by passing the host parameter to it, like this:

```ruby
client = ThreeScale::Client.new(:provider_key => "your provider key", :host => "your.varnish.net:8080")
```

that's it, your API should now be authorized and reported for you, and all that at full speed.

### Authorize

To authorize an application, call the +authorize+ method passing it the application's id and
optionally a key:

```ruby
response = client.authorize(:app_id => "the app id", :app_key => "the app key")
```

Then call the +success?+ method on the returned object to see if the authorization was
successful.

```ruby
if response.success?
  # All fine, the usage will be reported automatically. Proceeed.
else
  # Something's wrong with this application.
end
```

If both provider key and app id are valid, the response object contains additional
information about the status of the application:

```ruby
# Returns the name of the plan the application is signed up to.
response.plan
```

If the plan has defined usage limits, the response contains details about the usage broken
down by the metrics and usage limit periods.

```ruby
# The usage_reports array contains one element per each usage limit defined on the plan.
usage_report = response.usage_reports[0]

# The metric
usage_report.metric # "hits"

# The period the limit applies to
usage_report.period        # :day
usage_report.period_start  # "Wed Apr 28 00:00:00 +0200 2010"
usage_report.period_end    # "Wed Apr 28 23:59:59 +0200 2010"

# The current value the application already consumed in the period
usage_report.current_value # 8032

# The maximal value allowed by the limit in the period
usage_report.max_value     # 10000

# If the limit is exceeded, this will be true, otherwise false:
usage_report.exceeded?     # false
```

If the authorization failed, the +error_code+ returns system error code and +error_message+
human readable error description:

```ruby
response.error_code    # "usage_limits_exceeded"
response.error_message # "Usage limits are exceeded"
```

### OAuth Authorize

To authorize an application with OAuth, call the +oauth_authorize+ method passing it the application's id.

```ruby
response = client.oauth_authorize(:app_id => "the app id")
```

If the authorization is successful, the response will contain the +app_key+ and +redirect_url+ defined for this application:

```ruby
response.app_key
response.redirect_url
```

### Report

To report usage, use the +report+ method. You can report multiple transaction at the same time:

```ruby
response = client.report({:app_id => "first app id",  :usage => {'hits' => 1}},
                         {:app_id => "second app id", :usage => {'hits' => 1}})
```

The :app_id and :usage parameters are required. Additionaly, you can specify a timestamp
of transaction:

```ruby
response = client.report({:app_id => "app id", :usage => {'hits' => 1},
                          :timestamp => Time.local(2010, 4, 28, 12, 36)})
```

The timestamp can be either a Time object (from ruby's standard library) or something that
"quacks" like it (for example, the ActiveSupport::TimeWithZone from Rails) or a string. The
string has to be in a format parseable by the Time.parse method. For example:

```ruby
"2010-04-28 12:38:33 +0200"
```

If the timestamp is not in UTC, you have to specify a time offset. That's the "+0200"
(two hours ahead of the Universal Coordinate Time) in the example abowe.

Then call the +success?+ method on the returned response object to see if the report was
successful.

```ruby
  if response.success?
    # All OK.
  else
    # There was an error.
  end
```

In case of error, the +error_code+ returns system error code and +error_message+
human readable error description:

```ruby
response.error_code    # "provider_key_invalid"
response.error_message # "provider key \"foo\" is invalid"
```


## Rack Middleware

You can use our Rack middleware to automatically authenticate your Rack applications.

```ruby
use ThreeScale::Middleware, provider_key, :user_key # or :app_id
```
