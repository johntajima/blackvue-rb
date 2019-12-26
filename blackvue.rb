#!/usr/bin/env ruby

require 'open-uri'
require 'fileutils'
require 'logger'
require 'yaml'
require 'optparse'

USER_CONFIG = File.expand_path("~/.blackvue_config.yml")
DEFAULT_CONFIG = {
  "DASHCAM_IP"   => "192.168.2.111",
  "STORAGE_PATH" => "./blackvue_videos"
}


class Cam

  VERSION_PATH       = "/Config/version.bin"
  CONFIG_PATH        = "/Config/config.ini"
  FILES_PATH         = "/blackvue_vod.cgi"
  LIVEVIEW_PATH      = "/blackvue_live.cgi"
  REAR_LIVEVIEW_PATH = "/blackvue_live.cgi?direction=R"
  MB                 = 1000 * 1000

  attr_reader :download_path, :base_url, :config

  def initialize(config = DEFAULT_CONFIG)
    @config        = config
    @base_url      = "http://#{@config.fetch("DASHCAM_IP")}"
    @download_path = File.expand_path(@config.fetch("STORAGE_PATH"))
  end

  def version
    url = File.join(base_url, VERSION_PATH)
    get(url)
  end

  def files
    url = File.join(base_url, FILES_PATH)
    response = get(url)
    _, list = response.split("\n").partition {|entry| entry.start_with?("v:") }
    list.map {|entry| entry.split(",").first.gsub(/^n\:/,'') }
  end

  def download(file, path: download_path)
    dest   = File.join(File.expand_path(path), File.basename(file))
    source = File.join(base_url, file)
    if dest_exists?(dest)
      logger.debug("#{dest} already exists...skipping")
      return
    else
      start_time = Time.now
      logger.debug("Downloading [#{source}]")
      File.open(dest, 'w') {|f| IO.copy_stream(open(source), f) }
      log_report(dest, start_time)
    end
  rescue Errno::EHOSTUNREACH, Net::OpenTimeout => e
    logger.info("[ERROR] #{e.message}")
  end


  private

  def log_report(dest, start_time)
    duration = Time.now - start_time
    size = File.size(dest).to_f / MB
    logger.debug("Download complete [#{dest}] [#{"%.02f" % duration}s] [#{"%.02f" % size}mb] [#{"%.04f" % (size / duration)} mb/s]")
  end

  def dest_exists?(file)
    File.exists?(file) && File.size(file) >= (10 * MB)
  end

  def get(url)
    open(read).read.gsub(/\r\n/, "\n")
  rescue Errno::EHOSTUNREACH, Net::OpenTimeout => e
    logger.info("[ERROR] #{e.message} executing #{url}")
  end

  def logger
    @logger ||= begin
      logger = Logger.new(STDOUT)
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime("%H:%M:%S")}: #{msg}\n"
      end
      logger
    end
  end
end

SETTINGS ||= begin
  default_config = DEFAULT_CONFIG
  custom_config  = File.exist?(USER_CONFIG) ? YAML.load(File.open(USER_CONFIG).read) : {}
  default_config.merge(custom_config)
end

@options = {}
OptionParser.new do |opts|
  opts.on("-v", "--verbose", "Verbose Mode") do
    @options[:verbose] = true
  end
  opts.on("-l", "--list", "List all files") do
    @options[:action] = "list"
  end
  opts.on("-d", "--download", "Download all files") do
    @options[:action] = "download"
  end
  opts.on("-i", "--info", "Displays info") do
    @options[:action] = "info"
  end
end.parse!(into: @options)

cam = Cam.new(SETTINGS)
if @options.empty?
  puts SETTINGS
  puts "Found #{cam.files.count} files.\n#{cam.version}"
  exit
end

case @options[:action]
when 'list'
  files = cam.files
  puts files
  puts "found #{cam.files.count} files"  
when 'download'
  FileUtils.mkdir_p SETTINGS['STORAGE_PATH'] unless File.directory?(SETTINGS['STORAGE_PATH'])
  cam.files.each {|file| cam.download(file) }
when 'info'
  puts cam.version
  puts 
  puts SETTINGS
else
  p "Nothing to do."
end

