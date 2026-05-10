#!/usr/bin/ruby

require "FileUtils"
require "JSON"
require "net/http"
require "uri"

BASE_URL = "https://api.todoist.com"

CONFIG_DIR = File.join(Dir.home, ".config", "focus-task")
STATE_DIR = File.join(Dir.home, ".local", "state", "focus-task")

def config_path
  File.join(CONFIG_DIR, "config.json")
end

def state_path
  File.join(STATE_DIR, "state.json")
end

def load_config
  return {} unless File.exist?(config_path)
  JSON.parse(File.read(config_path))
end

def save_config(data)
  FileUtils.mkdir_p(CONFIG_DIR)
  File.write(config_path, JSON.pretty_generate(data))
  File.chmod(0600, config_path)
end

def load_state
  return nil unless File.exist?(state_path)
  data = JSON.parse(File.read(state_path))
  Task.new(id: data["id"], content: data["content"], priority: data["priority"])
end

def save_state(task)
  FileUtils.mkdir_p(STATE_DIR)
  File.write(state_path, JSON.pretty_generate({ id: task.id, content: task.content, priority: task.priority }))
end

def clear_state
  File.delete(state_path) if File.exist?(state_path)
end

def load_or_prompt_api_key
  config = load_config
  api_key = config["api_key"]
  if !api_key
    puts("Input your Todoist API key:")
    api_key = gets().strip
    puts("Save key (y/n)? Do not do this if you are using a public computer.")
    if gets&.strip&.downcase == "y"
      save_config({ api_key: api_key })
    end
  end
  api_key
end


Task = Struct.new(:id, :content, :priority, keyword_init: true)

def get_tasks_from_api(query = "(today | overdue) & !assigned to: others")
  api_key = load_or_prompt_api_key

  path = "api/v1/tasks/filter"
  uri = URI.join(BASE_URL, path)
  uri.query = URI.encode_www_form({ query: query })

  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{api_key}"
  request["Content-Type"] = "application/json"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
    http.request(request)
  end

  parse_results((JSON.parse(response.body))["results"])
end

def parse_results(results = [])
  results.map do |task|
    Task.new(id: task["id"], content: task["content"], priority: task["priority"].to_i)
  end
end

def get_random_task
  tasks = get_tasks_from_api
  highest_priority = tasks.map { |task| task.priority }.max
  tasks.filter { |task| task.priority == highest_priority }.sample
end

def complete_task_in_api(task_id)
  api_key = load_or_prompt_api_key

  uri = URI.join(BASE_URL, "api/v1/tasks/#{task_id}/close")

  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{api_key}"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPNoContent)
    puts "Error marking task complete (HTTP #{response.code}): #{response.body}"
    exit 1
  end
rescue Net::OpenTimeout, Net::ReadTimeout
  puts "Error: request to Todoist timed out."
  exit 1
rescue SocketError => e
  puts "Error: could not connect to Todoist (#{e.message})."
  exit 1
end


command = ARGV[0]

case command
when "display"
  task = load_state
  if task
    puts task.content
  else
    puts "No focus task stored. Run without arguments to fetch one."
    exit 1
  end
when "complete"
  task = load_state
  if task
    complete_task_in_api(task.id)
    clear_state
    puts "Marked complete: #{task.content}"
  else
    puts "No focus task stored. Run without arguments to fetch one."
    exit 1
  end
else
  task = get_random_task
  save_state(task)
  puts task.content
end
