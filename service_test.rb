require "resque"
require "json"

$id = 210
REQ_PER_SEC = 5
THINK_TIME = 1.0 / REQ_PER_SEC
NUMBER_ITERATIONS = 30
LOG_FILE = "test_start_log" #+ Time.now.strftime("%Y-%m-%d_%H:%M:%S")
TASKS_PATH = "Tasks"

TASKS_TO_TEST = :all
LANGUAGES_TO_TEST = ['CPP']

def enqueue_submission(source, task, lang, id)
  job = {
      :source => source,
      :task => task,
      :lang => lang,
      :id => id,
      :destination_queue => 'qa_ToC'
  }
  queue = "submissions"
  worker_class = "worker.SubmissionChecker"
  Resque.push(queue, :class => worker_class, :args => [job])
end

def log_request(task, lang, id, source_file)
  log = {
      :id => id,
      :time => Time.now.to_f,
      :lang => lang,
      :task => task,
      :source_file => source_file
  }.to_json
  File.open( LOG_FILE, 'a+') {|file| file.puts(log) }
end

def send_source(lang,task,source_file)
  file = File.open(File.join(TASKS_PATH, lang,task,source_file), "r")
  source = file.read
  #puts  "task #{task} lang #{lang} id #{$id}"
  #puts "source #{source}"
  file.close
  enqueue_submission(source, task, lang, $id)
  log_request(task, lang, $id, source_file)
  $id = $id + 1
  sleep(THINK_TIME)
end

def get_sources(task)
  sources = {}
  Dir.chdir(task) do
    sources = Dir.glob ("*")
  end
  sources
end

def get_tasks(lang)
  tasks = {}
  Dir.chdir(lang) do
    Dir.glob ("*") do |task_dir|
      tasks[task_dir] = get_sources(task_dir)
    end
  end
  tasks
end

def get_languages()
  langs = {}
  Dir.chdir(TASKS_PATH) do
    Dir.glob ("*") do |lang_dir|
      langs[lang_dir] = get_tasks(lang_dir)
    end
  end
  langs
end

def prepare_test()
  langs = get_languages()
  if LANGUAGES_TO_TEST != :all
    langs.keep_if {|lang, tasks| LANGUAGES_TO_TEST.include?(lang) }
  end

  if TASKS_TO_TEST != :all
    langs.each_key do |lang, tasks|
      tasks.keep_if {|task, sources| TASKS_TO_TEST.include?(task) }
    end
  end

  langs
end

def add_next_random_task(langs)
  lsize = langs.length
  lang, tasks = langs.to_a[rand(lsize)]
  tsize = tasks.length
  task, sources = tasks.to_a[rand(tsize)]
  ssize = sources.length
  source = sources.to_a[rand(ssize)]

  send_source(lang, task,source)
end

File.delete(LOG_FILE) if File.exists?(LOG_FILE)
puts langs = prepare_test
NUMBER_ITERATIONS.times {add_next_random_task(langs)}