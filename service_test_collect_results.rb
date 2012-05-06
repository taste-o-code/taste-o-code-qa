require 'resque'
require 'json'
require 'gruff'
require 'yaml'

START_LOG_FILE = 'test_start_log' #2012-04-23_17:10:25'
QUEUE = 'qa_ToC'
RESULT_TYPES = [:correct, :incorrect, :unknown]

def pop_submission_result(submission_results)
  submission_result = Resque.pop QUEUE
  args = submission_result['args']
  id = args[0]['id']
  submission_results[id] = {
    result: args[0]['result'],
    fail_cause: args[0]['fail_cause'],
    finish_time:args[0]['finish_time'],
    start_time:args[0]['start_time']
  }
end


def collect_submission_data(submission_results)
  submissions = {}
  File.open( START_LOG_FILE, 'a+') do |file|
    file.each do |line|
      submission = JSON.parse(line)
      new_submission =  {
          :lang => submission['lang'],
          :task => submission['task'],
          :source_file => submission['source_file'],
          :submit_time => submission['time']
      }

      if submission_results.key? submission['id']
        submission_result = submission_results[submission['id']]
        if (/^A-/.match(submission['source_file']) && submission_result[:result] == 'accepted') or
            (/^F-/.match(submission['source_file']) && submission_result[:result] == 'failed')
          result = :correct
        else
          result = :incorrect
        end

        new_submission[:start_time] = submission_result[:start_time]
        new_submission[:finish_time] = submission_result[:finish_time]
        new_submission[:fail_cause] = submission_result[:fail_cause]
      else
        result = :unknown
      end
      new_submission[:result] = result
      submissions[submission['id']] = new_submission
    end
  end
  submissions.values
end

def collect_submissions_results()
  submission_results = {}
  while (Resque.size QUEUE).to_i != 0
    pop_submission_result(submission_results)
  end
  submission_results
end

def get_langs_tasks(submissions)
  langs = submissions.map { |value| value[:lang] }.uniq
  langs_tasks = {}
  langs.each do |lang|
    tasks = submissions.select { |value| value[:lang] == lang }
                     .map { |value| value[:task] }.uniq
    langs_tasks[lang] = tasks
  end
  puts "Langs:" + langs_tasks.to_yaml
  langs_tasks
end

def get_errors_summary (submissions)
  errors_summary = {}
  RESULT_TYPES.each do |type|
    errors_summary[type] = submissions.count { |value| value[:result] == type}
  end
  errors_summary
end

def get_average_summary (submissions)
  average_summary = {}
  average_summary[:wait_time] = 0
  average_summary[:work_time] = 0

  if submissions.size > 0
    submissions.each do |value|
      if value[:result] != :unknown
        average_summary[:wait_time] += (value[:start_time] - value[:submit_time]).round 3
        average_summary[:work_time] += (value[:finish_time] - value[:start_time]).round 3
      end
    end
  average_summary[:wait_time] /= submissions.size
  average_summary[:work_time] /= submissions.size
  end

  average_summary
end

def get_summary(submissions, langs_tasks)
  summary = {}
  summary['Total'] = get_errors_summary(submissions).merge(get_average_summary(submissions))

  langs_tasks.keys.each do |lang|
    lang_submissions = submissions.select { |value| value[:lang] == lang }
    lang_results = get_errors_summary(lang_submissions).merge(get_average_summary(lang_submissions))

    langs_tasks[lang].each do |task|
      task_submissions = lang_submissions.select { |value| value[:task] == task }
      task_results = get_errors_summary(task_submissions).merge(get_average_summary(task_submissions))

      lang_results[task] = task_results
    end
    summary[lang] =  lang_results

  end
  summary
end

def get_summary_keynote_pie_graphs(summary)
  summary.each do |lang, result|
    g = Gruff::Pie.new
    g.title = lang
    RESULT_TYPES.each {|type| g.data type.to_s, result[type]}
    g.write("pie_keynote_" + lang + ".png")
  end
end

def get_errors_stacked_graphs(summary, langs_tasks)
  summary.each do |lang, result|
    if langs_tasks.key? lang
      g = Gruff::StackedBar.new
      g.title = lang + " Errors"
      types = {}
      RESULT_TYPES.each { |type| types[type] = [] }
      langs_tasks[lang].each_index do |i|
        task = langs_tasks[lang][i]
        RESULT_TYPES.each { |type| types[type] << result[task][type] }
        g.labels[i] = task
      end
      types.each { |type, data| g.data type.to_s, data }
      g.sort = false
      g.write("errors_stacked_" + lang + ".png")
    end
  end
end

def get_detailed_average_bar_graphs(summary, langs_tasks)
  summary.each do |lang, result|
    if langs_tasks.key? lang
        g = Gruff::Bar.new
        g.title = lang + " Average Response Time"
        data = []
        langs_tasks[lang].each_index do |i|
          task = langs_tasks[lang][i]
          data[i] = result[task][:work_time].round 3
          g.labels[i] = task
        end
        g.data 'average res time, sec', data
        g.sort = false
        g.minimum_value = 0
        g.write("average_bar_" + lang + ".png")
      end
  end
end

def get_total_average_bar_graphs(summary)
  g = Gruff::SideBar.new
  g.title = 'Average Response Time'
  data = []
  for i in 0..summary.size - 1
    data[i] = summary.values[i][:work_time].round 3
    g.labels[i] = summary.keys[i]
  end
  g.data 'average res time, sec', data
  g.sort = false
  g.minimum_value = 0
  g.write("average_bar.png")
end

def draw_response_time_area_graphs(submissions, langs_tasks)
  langs_tasks.keys.each do |lang|
    lang_submissions = submissions.select { |value| value[:lang] == lang }
    draw_response_time_line_graph(lang_submissions, lang, langs_tasks[lang])
    g = Gruff::Area.new
    g.title = lang + " Response Times"
    data_work = []

    lang_submissions.each do |value|
      if value[:result] != :unknown
        data_work << ((value[:finish_time] - value[:start_time]).round 3)
      end
    end

    g.data 'work time, sec', data_work
    g.minimum_value = 0
    g.write "response_times_area_" + lang + ".png"

  end
end

def draw_response_time_line_graph(submissions, lang, tasks)
  g = Gruff::Line.new
  g.title = lang + " " + " Response Times by Tasks"
  tasks.each do |task|
    task_submissions = submissions.select { |value| value[:task]== task }

    data_work = []
    task_submissions.each do |value|
      if value[:result] != :unknown
        data_work << ((value[:finish_time] - value[:start_time]).round 3)
      end
    end

    g.data task, data_work
  end

  g.minimum_value = 0
  g.write "response_times_line_" + lang + ".png"
end

def draw_total_response_time_area_graph(submissions)
    g = Gruff::Area.new
    g.title = 'Total Response Times'
    data_wait = []
    data_all = []

    submissions.each do |value|
      if value[:result] != :unknown
        data_wait << ((value[:start_time] - value[:submit_time]).round 3)
        data_all << ((value[:finish_time] - value[:submit_time]).round 3)
      end
    end

    g.data 'wait time, sec', data_wait
    g.data 'work time, sec', data_all
    g.minimum_value = 0
    g.write "response_times_area_total.png"
end


submission_results = collect_submissions_results
submissions = collect_submission_data(submission_results)
#puts submissions.to_yaml

langs_tasks = get_langs_tasks(submissions)
summary = get_summary(submissions, langs_tasks)
#puts summary.to_yaml
get_summary_keynote_pie_graphs(summary)
get_errors_stacked_graphs(summary, langs_tasks)
get_detailed_average_bar_graphs(summary, langs_tasks)
get_total_average_bar_graphs(summary.select { |key,value| langs_tasks.key? key})
draw_total_response_time_area_graph(submissions)
draw_response_time_area_graphs(submissions, langs_tasks)