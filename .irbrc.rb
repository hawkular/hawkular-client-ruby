lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hawkular/hawkular_client'
require 'hawkular/version'
require 'irb/completion'

class String
  def cyan; "\e[36m#{self}\e[0m" end
end

puts %q[
                       _          _                ___   _            _
  /\  /\__ ___      __| | ___   _| | __ _ _ __    / __\ (_) ___ _ __ | |_ 
 / /_/ / _` \ \ /\ / /| |/ / | | | |/ _` | '__|  / /  | | |/ _ \ '_ \| __|
/ __  / (_| |\ V  V / |   <| |_| | | (_| | |    / /___| | |  __/ | | | |_ 
\/ /_/ \__,_| \_/\_/  |_|\_\\\\__,_|_|\__,_|_|    \____/|_|_|\___|_| |_|\__|].cyan
puts "                                                                  (v#{Hawkular::VERSION})"
puts 'type h for help'


IRB.conf[:PROMPT][:HAWKULAR_PROMPT] = {
  AUTO_INDENT: false,          # enables auto-indent mode
  PROMPT_I: " %m ► ",         # simple prompt
  PROMPT_S: "",              # prompt for continuated strings
  PROMPT_C: " %m..",           # prompt for continuated statement
  RETURN: "  = %s\n"          # format to return value
}
IRB.conf[:PROMPT_MODE] = :HAWKULAR_PROMPT
IRB.conf[:SAVE_HISTORY] = 5000

def connect
  puts 'connecting...'
  client = ::Hawkular::Client.new(entrypoint: 'http://localhost:8080', 
                                  credentials: { username: 'jdoe',
                                                 password: 'password'
                                               }
                                 )
  cd client
  'Now type: inventory.list_feeds, metrics.counters.get_data 42, cd inventory, etc.'
end
alias :c :connect

def hhelp
  puts 'c, connect ... does foo'
  puts 'h, hhelp   ... does bar'
  puts
end
alias :h :hhelp

def cd(object = nil)
  if object.nil?
    irb_pop_binding
    'usage: cd inventory / cd ..'
  elsif object == '..'
    irb_pop_binding
  else
    irb_push_binding object
    'context changed'
  end
end

def back
  cd '..'
end

def ls
  'Methods: ' + (self.class.instance_methods(false) + [:back, :cd, :c, :connect, :h, :hhelp, :ls])
                    .map { |m| m.to_s }.to_s.gsub('"', '')
end