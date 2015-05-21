require "signupster/version"
require 'shopify_api'
require 'uri'
require 'securerandom'
require 'rest-client'
require 'nokogiri'

module Signupster
  def self.create_shop(shop_name, owner_name, owner_email, password)
    signup_hash = {
      _y: SecureRandom.uuid,
      ref: "",
      ssid: "",
      source: "",
      signup_code: "",
      forwarded_host: "www.shopify.com",
      signup: {
        shop_name: shop_name,
        first_name: owner_name,
        last_name: owner_name,
        email: owner_email,
        password: password,
        extra: "",
        pos: "",
        signup_types: ""
      },
      utf8: "✓",
    }

    config_hash = {
      online: "1",
      retail: "0",
      first_name: owner_name,
      last_name: owner_name,
      address1: "the internet",
      city: "LA",
      zip: "90210",
      province: "California",
      country: "US",
      phone: "5555555555",
      background: "I'm just playing around",
      previous_platform: "",
      business_revenue: "$0 (I'm just getting started)",
      potential_partner: "0"
    }

    puts "creating a shop"
    result = RestClient.post("https://app.shopify.com/services/signup/create", signup_hash)

    puts "redirected to shop admin"
    redirect_url = result.headers[:location]
    puts redirect_url
    puts "you can log into your shop here: #{redirect_url}"

    puts "logging you in automagically"
    admin_url = URI.parse(redirect_url)
    login_cookie = nil
    result = RestClient.post("https://#{admin_url.host}/admin/auth/login", {login: owner_email, password: password}) do |response, request, result, &block|
      login_cookie = response.headers[:set_cookie].join(";").scan(/_secure_admin_session_id=([a-z0-9]*);/).first.first
    end

    puts "grabbing authenticity_token"
    page = Nokogiri::HTML(RestClient.get("https://#{admin_url.host}/admin/account_setup/", :cookies => {"_secure_admin_session_id" => login_cookie}))
    authenticity_token = page.css('input[name="authenticity_token"]')[0]["value"]

    puts "okay, setting up your shop"
    result = RestClient.post("https://#{admin_url.host}/admin/account_setup/",
                             {:account_setup => config_hash, "authenticity_token" => authenticity_token}, 
                             {"Cookie" => "_secure_admin_session_id=#{login_cookie}"})


    puts "okay, your shop is setup. generating an api key"

    page = Nokogiri::HTML(RestClient.get("https://#{admin_url.host}/admin/apps/private/new", :cookies => {"_secure_admin_session_id" => login_cookie}))
    authenticity_token = page.css("input[name='authenticity_token']")[0]["value"]

    app_page = nil
    result = RestClient.post("https://#{admin_url.host}/admin/apps/private",
                             {"authenticity_token" => authenticity_token, "api_client" => {"title" => "its go time", "contact_email"=>owner_email}},
                             {"Cookie" => "_secure_admin_session_id=#{login_cookie}"}) do |res, req, result, &block|
                               app_page = res.headers[:location]
                             end

    page = RestClient.get(app_page, :cookies => {"_secure_admin_session_id" => login_cookie})

    # lol ghetto++
    authurl = "https://#{page.body.scan(/https\:\/\/([a-z0-9\:]*)@/)[1][0]}@#{admin_url.host}/admin"

    upload_theme(authurl)
  end

  def self.upload_theme(auth_url)
    ShopifyAPI::Base.site = auth_url
    puts "uploading minimalist theme"

    ShopifyAPI::Theme.new(name: "ultramin", src: "https://github.com/orenmazor/signupster/raw/master/theme.zip", role: "main").save! 
  end
end
