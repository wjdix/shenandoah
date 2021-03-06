require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'spec/interop/test'
require 'rspec_hpricot_matchers'
require 'rack/test'
require 'time'
require 'fileutils'

require 'shenandoah/server'
require 'shenandoah/locator'

describe Shenandoah::Server do
  include Rack::Test::Methods
  include FileUtils
  include Shenandoah::Spec::Tmpfile

  def app
    Shenandoah::Server
  end

  before do
    app.set :environment, :test
  end

  describe "/shenandoah/browser-runner.js" do
    before do
      get '/shenandoah/browser-runner.js'
    end

    it "is accessible" do
      last_response.should be_ok
    end

    it "is javascript" do
      last_response.headers['Content-Type'].should == 'text/javascript'
    end

    it "includes jQuery" do
      last_response.body.should =~ %r{\* jQuery JavaScript Library v1\.3\.2}
    end

    it "includes jQuery.fn" do
      last_response.body.should =~ %r{\$.fn.fn = function}
    end

    it "includes jQuery.print" do
      last_response.body.should =~ %r{\$.print = function}
    end

    it "includes Screw.Unit" do
      last_response.body.should =~ %r{var Screw = \(function\(\$\)}
    end

    it "includes Smoke" do
      last_response.body.should =~ %r{Smoke = \{}
    end

    it "includes the Shenandoah test API" do
      last_response.body.should =~ %r{function require_spec\(}
      last_response.body.should =~ %r{function require_main\(}
    end

    it "includes the multirunner code for a single test" do
      last_response.body.should =~ %r{window.parent.jQuery\('iframe'\)}
    end

    it "was last modified at the latest date of the combined files" do
      maxTime = Dir["#{File.dirname(__FILE__)}/../../lib/shenandoah/javascript/{browser,common}/*.js"].
        reject { |filename| filename =~ /multirunner.js$/ || filename =~ /parsequery/i || filename =~ /index.js$/ }.
        collect { |filename| File.stat(filename).mtime }.max
      Time.httpdate(last_response.headers['Last-Modified']).should == maxTime
    end

    it "includes the source filenames" do
      last_response.body.should =~ %r{////// javascript/common/jquery-1.3.2.js}
    end
  end

  %w(main spec).each do |kind|
    describe "/#{kind}/*" do
      before do
        app.set :locator,
          Shenandoah::DefaultLocator.new(
            :"#{kind}_path" => "#{self.tmpdir}/#{kind.hash}")
      end

      describe "for an existing file" do
        before do
          tmpfile("#{kind.hash}/good.js", "var any = function () { };\n")
          get "/#{kind}/good.js"
        end

        it "succeeds" do
          last_response.should be_ok
        end

        it "responds with the content" do
          last_response.body.should == "var any = function () { };\n"
        end

        it "indicates that the file shouldn't be cached" do
          last_response.headers["Cache-Control"].should == "no-cache"
        end
      end

      describe "for a non-existent file" do
        before do
          get "/#{kind}/bad.js"
        end

        it "404s" do
          last_response.status.should == 404
        end

        it "has a reasonable error message" do
          last_response.body.should ==
            "#{kind.capitalize} file not found: #{self.tmpdir}/#{kind.hash}/bad.js"
        end
      end
    end
  end

  describe "/shenandoah.css" do
    describe "by default" do
      before do
        get '/shenandoah.css'
        @sass = File.expand_path(
          "lib/shenandoah/css/shenandoah.sass", File.dirname(__FILE__) + "/../..")
      end

      it "is available" do
        last_response.should be_ok
      end

      it "is the CSS version of the included shenandoah.sass" do
        last_response.body.should include('#frames iframe {')
        last_response.body.should include('.describes .describe {')
      end

      it "includes the compass reset styles directly" do
        last_response.body.should_not include("@import url(compass/reset.css)")
        last_response.body.should include("table, caption, tbody, tfoot, thead, tr, th, td")
      end

      it "has the correct last modified version" do
        Time.httpdate(last_response.headers['Last-Modified']).should ==
          File.stat(@sass).mtime
      end

      it "is CSS" do
        last_response.content_type.should == 'text/css'
      end
    end

    describe "when overridden with CSS" do
      before do
        app.set :locator,
          Shenandoah::DefaultLocator.new(:spec_path => self.tmpdir)
        tmpfile "shenandoah.css", ".passed { color: blue }"
        get '/shenandoah.css'
      end

      it "is available" do
        last_response.should be_ok
      end

      it "is the version from the spec dir" do
        last_response.body.should == ".passed { color: blue }"
      end

      it "has the correct last modified version" do
        Time.httpdate(last_response.headers['Last-Modified']).should ==
          File.stat("#{self.tmpdir}/shenandoah.css").mtime
      end

      it "is CSS" do
        last_response.content_type.should == 'text/css'
      end
    end

    describe "when overridden with Sass" do
      before do
        app.set :locator,
          Shenandoah::DefaultLocator.new(:spec_path => self.tmpdir)
        tmpfile "shenandoah.sass", ".passed\n  color: blue"
        get '/shenandoah.css'
      end

      it "is available" do
        last_response.should be_ok
      end

      it "is the version from the spec dir" do
        last_response.body.should == ".passed {\n  color: blue; }\n"
      end

      it "has the correct last modified version" do
        Time.httpdate(last_response.headers['Last-Modified']).should ==
          File.stat("#{self.tmpdir}/shenandoah.sass").mtime
      end

      it "is CSS" do
        last_response.content_type.should == 'text/css'
      end
    end
  end

  describe "/screw.css" do
    before do
      get '/screw.css'
    end

    it "redirects" do
      last_response.status.should == 301
    end

    it "points to /shenandoah.css" do
      last_response['Location'].should == '/shenandoah.css'
    end

    it "includes a deprecation note" do
      last_response.body.should == "This URI is deprecated.  Use <a href='/shenandoah.css'>/shenandoah.css</a>."
    end
  end

  describe "/" do
    include RspecHpricotMatchers

    before do
      app.set :locator,
        Shenandoah::DefaultLocator.new(:spec_path => File.join(self.tmpdir, 'spec'))
      tmpfile "spec/common_spec.js", "DC"
      tmpfile "spec/application_spec.js", "DC"
      tmpfile "spec/some/thing_spec.js", "DC"
      get "/"
    end

    it "is available" do
      last_response.should be_ok
    end

    it "includes an overall heading" do
      app.set :project_name, "Some Proj"
      get "/"
      last_response.body.should have_tag("h1", "Specs for Some Proj")
    end

    it "does not include an overall heading without the project name" do
      app.set :project_name, nil
      get "/"
      last_response.body.should_not have_tag("h1")
    end

    it "includes a section heading for the root set" do
      last_response.body.should have_tag("h2", "[root]")
    end

    it "includes a section heading for each subdirectory" do
      last_response.body.should have_tag("h2", "some")
    end

    it "includes lists of links" do
      last_response.body.should have_tag("ul a", :count => 3)
    end

    it "includes a link to a spec in the root" do
      last_response.body.should have_tag("a[@href='/spec/common.html']", "common")
    end

    it "includes link to a spec in a subdirectory" do
      last_response.body.should have_tag("a[@href='/spec/some/thing.html']", "thing")
    end

    it "includes a checkbox for a spec in the root" do
      last_response.body.should have_tag("input[@value='/spec/common.html']")
    end

    it "includes a checkbox for a spec in a subdirectory" do
      last_response.body.should have_tag("input[@value='/spec/some/thing.html']")
    end

    it "includes a form to run the multirunner" do
      last_response.body.should have_tag("form[@action='/multirunner']")
    end

    it "includes a submit button for the multirunner form" do
      last_response.body.should have_tag("input[@type='submit']")
    end
  end

  describe "/multirunner" do
    include RspecHpricotMatchers

    before do
      get "/multirunner?spec=/spec/common.html"
    end

    it "is available" do
      last_response.should be_ok
    end

    it "is html" do
      last_response.content_type.should == 'text/html'
    end

    it "includes the multirunner script" do
      last_response.body.should have_tag("script[@src='/shenandoah/multirunner.js']")
    end

    it "includes the container" do
      last_response.body.should have_tag("div#runner")
    end
  end

  describe "/shenandoah/multirunner.js" do
    before do
      get '/shenandoah/multirunner.js'
    end

    it "is available" do
      last_response.should be_ok
    end

    it "is javascript" do
      last_response.content_type.should == 'text/javascript'
    end

    it "contains the multirunner script" do
      last_response.body.should =~ /shenandoah.Multirunner/
    end

    it "includes jQuery" do
      last_response.body.should =~ %r{\* jQuery JavaScript Library v1\.3\.2}
    end

    it "includes parseQuery" do
      last_response.body.should =~ %r{jQuery.parseQuery =}
    end
  end

  describe "/js/common/jquery-1.3.2.js" do
    before do
      get '/js/common/jquery-1.3.2.js'
    end

    it "is available" do
      last_response.should be_ok
    end

    it "is javascript" do
      last_response.content_type.should == 'application/javascript'
    end

    it "includes jQuery" do
      last_response.body.should =~ %r{\* jQuery JavaScript Library v1\.3\.2}
    end
  end
end
