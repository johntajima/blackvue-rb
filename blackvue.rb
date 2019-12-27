#!/usr/bin/env ruby

require 'fileutils'
require 'logger'
require 'yaml'
require 'optparse'

CAMERA_TYPES   = ['F', 'R']
VIDEO_TYPES    = ['N', 'E', 'P', 'M']
VALID_ACTIONS  = ['info', 'download', 'list']
USER_CONFIG    = File.expand_path("~/.blackvue_config.yml")
DEFAULT_CONFIG = {
  "DASHCAM_IP"   => "192.168.2.111",
  "STORAGE_PATH" => "./blackvue_videos",
  "VIDEO_TYPE"   => VIDEO_TYPES,
  "CAMERA_TYPE"  => CAMERA_TYPES
}


class Cam

  require 'open-uri'
  require 'fileutils'

  VERSION_PATH       = "/Config/version.bin"
  CONFIG_PATH        = "/Config/config.ini"
  FILES_PATH         = "/blackvue_vod.cgi"
  LIVEVIEW_PATH      = "/blackvue_live.cgi"
  REAR_LIVEVIEW_PATH = "/blackvue_live.cgi?direction=R"
  MB                 = 1000 * 1000
  CAMERA_INDEX       = -5
  VIDEO_INDEX        = -6

  attr_reader :storage_path, :base_url, :config

  def initialize(config)
    @config       = config
    @base_url     = "http://#{@config.fetch(:dashcam_ip)}"
    @storage_path = File.expand_path(@config.fetch(:storage_path))
  end

  def version
    url = File.join(base_url, VERSION_PATH)
    get(url)
  end

  def files
    if response = get(File.join(base_url, FILES_PATH))
      list = response.split("\n").drop(1)
      temp_list = list.map do |entry| 
        file = entry.split(",").first.gsub(/^n\:/,'') 
        valid_video_type?(file) ? file : nil
      end.compact.sort
    end
  end

  def download(file)
    dest   = File.join(storage_path, File.basename(file))
    source = File.join(base_url, file)

    if dest_exists?(dest)
      logger.debug("#{dest} already exists...skipping") && return
    else
      start_time = Time.now
      logger.debug("Downloading [#{source}]")
      File.open(dest, 'w') {|f| IO.copy_stream(open(source), f) }
      log_report(dest, start_time)
    end
  rescue Errno::EHOSTUNREACH, Errno::EHOSTDOWN => e
    logger.info("[ERROR] #{e.message}")
  end


  private

  def valid_video_type?(file)
    config[:camera_type].include?(file[CAMERA_INDEX]) &&
    config[:video_type].include?(file[VIDEO_INDEX])
  end

  def log_report(dest, start_time)
    duration = Time.now - start_time
    size = File.size(dest).to_f / MB
    logger.debug("Downloaded #{dest} (#{"%.02f" % size}mb in #{"%.02f" % duration}s) [#{"%.04f" % (size / duration)} mb/s]")
  end

  def dest_exists?(file)
    File.exists?(file) && File.size(file) >= (10 * MB)
  end

  def get(url)
    open(url).read.gsub(/\r\n/, "\n")
  rescue Errno::EHOSTUNREACH, Errno::EHOSTDOWN => e
    logger.info("[ERROR] #{e.message} executing #{url}")
    nil
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


def get_settings
  options = DEFAULT_CONFIG
  custom  = File.exist?(USER_CONFIG) ? YAML.load(File.open(USER_CONFIG).read) : {}
  options = options.merge(custom)
  options = options.inject({}){|memo,(k,v)| memo[k.downcase.to_sym] = v; memo}
  OptionParser.new do |opts|
    opts.banner = "Usage: blackvue.rb [command] [options]\n\n\tCommands are: list, download, info\n\n"

    opts.on("-i", "--ip dashcam_ip", String, "IP Address of Dashcam (eg: 192.168.2.111)") do |dashcam_ip|
      options[:dashcam_ip] = dashcam_ip
    end
    opts.on("-p", "--path storage_path", String, "Directory to download videos to") do |storage_path|
      options[:storage_path] = storage_path
    end
    opts.on("-t", "--type types", Array, "Video types [N,E,P,M] (default to all)") do |types|
      options[:video_type] = types.map(&:upcase).empty? ? VIDEO_TYPES : VIDEO_TYPES & types.map(&:upcase)
    end
    opts.on("-c", "--camera camera_type", Array, "Camera directions [F,R] (default to all)") do |camera_type|
      options[:camera_type] = camera_type.map(&:upcase).empty? ? CAMERA_TYPES : CAMERA_TYPES & camera_type.map(&:upcase)
    end
  end.parse!
  options[:action] = VALID_ACTIONS.include?(ARGV[0]) ? ARGV[0] : nil
  options
end

def run_command(options)
  cam = Cam.new(options)
  case options[:action]
  when 'list'
    if files = cam.files
      puts files
      puts "Found #{files.count} files"  
    else
      puts "No video files or error reading cam."
    end
  when 'download'
    path = options[:storage_path]
    FileUtils.mkdir_p(path) unless File.directory?(path)
    cam.files.each {|file| cam.download(file) }
  when 'info'
    puts cam.version
  else
    puts "Unknown command [#{options[:action]}]. Aborting."
  end
end



begin
  options = get_settings
  puts options
  run_command(options)
end






