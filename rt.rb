#!/home/w80/.rvm/rubies/ruby-2.6.3/bin/ruby
## rt.tb - a reimplementation in Ruby of t.py (https://github.com/sjl/t)

#MIT License
#
#Copyright (c) 2019 Dave Ryack
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.


require 'abbrev'
require 'digest'
require 'slop'

def _hash(text)
  Digest::SHA256.hexdigest text
end

def task_from_taskline(taskline)
  task = {}
  if taskline.start_with?('#')
    nil
  elsif taskline.include?('|')
    text, _, meta = taskline.partition('|')
    task = { text: text.strip }
    meta.strip.split(',').each do |piece|
      label, data = piece.split(':')
      task[label.strip.to_sym] = data
    end
  else
    text = taskline.strip
    task = { id: _hash(text), text: text }
  end
  task
end

def tasklines_from_tasks(tasks)
  tasklines = []

  tasks.each do |task|
    metatags = task[1].reject { |key| key == :id || key == :text || key == :done }
    msg = ""
    msg << "#{task[1][:text]} | id:#{task[1][:id]}"
    msg << " | " unless metatags.empty?
    metatags.each_pair { |a, b| msg << "#{a}:#{b},".chop }
    tasklines << msg + "\n"
  end
  tasklines
end

def prefixes(ids)
  prefix = Abbrev.abbrev(ids.keys)
                 .group_by { |_k, v| v }
                 .map { |k, v| [k, v.flatten.min_by(&:length)] }
                 .to_h
  prefix.invert
end

class InvalidTaskfile < StandardError
  def initialize(message)
    super(message)
  end
end

class AmbiguousPrefix < StandardError
  def initialize(message)
    super(message)
  end
end

class UnknownPrefix < StandardError
  def initialize(message)
    super(message)
  end
end

class BadFile < StandardError
  def initialize(message)
    super(message)
  end
end

class TaskDict
  def initialize(taskdir, name)
    @tasks = {}
    @done = {}
    @name = name
    @taskdir = taskdir
    filemap = { tasks: @name, done: ".#{@name}.done" }
    filemap.each_pair do |kind, filename|
      path = File.join(File.expand_path(@taskdir), filename)

      raise InvalidTaskfile if File.directory?(path)

      if File.exist?(path)
        File.open(path.to_s, 'r') do |tfile|
          tls = IO.readlines(tfile, strip: true) do |line|
            tls << line
          end
          tls.map do |x|
            y = task_from_taskline(x)
            y.each_key do |task|
              if task.empty?
                next
              else
                if kind.to_s === 'tasks'
                  @tasks[y[:id]] = y
                else
                  @done[y[:id]] = y if kind.to_s === 'done'
                end
              end
            end
          end
        end
      end
      @done.each_value { |x| x[:done] = true }
      @tasks.merge!(@done)
    end
  end

  def _get_item(prefix)
    matched = []
    @tasks.each_key do |tid|
      if tid.start_with?(prefix.to_s)
        matched << tid
      else
        next
      end
    end
    if matched.length == 1
      return @tasks[matched[0]]
    elsif matched.empty?
      raise UnknownPrefix, prefix
    else
      matched = @tasks.each_key { |tid| matched << tid if tid == prefix }
      if matched.length == 1
        return @tasks[matched[0]]
      else
        raise AmbiguousPrefix, prefix
      end
    end
  end

  def add_task(text)
    task_id = _hash(text)
    @tasks[task_id] = { id: task_id, text: text }
  end

  def edit_task(prefix, text)
    task = _get_item(prefix)
    # this section can be changed a fair bit in Ruby:
    # - /g should signal us to switch to .gsub() for the final assignment
    # - the intermediate partition process isn't really necessary in Ruby
    if text.start_with?('s/', '/')
      text = text.sub(%r{^s?/}, '').chomp('/')
      find, _, repl = text.partition('/')
      text = task[:text].sub(/#{find}/, repl)
    end

    task[:text] = text
    task[:id] = _hash(text)
  end

  def finish_task(prefix)
    task = _get_item(prefix)

    @done[task[:id]] = task
    @done[task[:id]][:done] = true
    @tasks.delete(task[:id])
  end

  def remove_task(prefix)
    task = _get_item(prefix)
		if task[:done]
      @done.delete(task[:id])
    else
      @tasks.delete(task[:id])
    end
  end

  def print_list(kind: 'tasks', verbose: false, quiet: false, grep: '')
    # FIXME there's almost certainly a more elegant way to accomplish this, but if we .select up front, we get incorrect prefixes
    tasks = @tasks
    label = verbose ? 'id' : 'prefix'
    unless verbose
      prefixes(tasks).each_pair do |prefix, task_id|
        tasks[task_id][:prefix] = prefix
      end
    end

    # included in the "fix me" above
    tasks = kind === 'tasks' ? @tasks.reject { |_, v| v[:done] } : @tasks.select { |_, v| v[:done] }
    # FIXME this bit is terrible, but i'm feeling impatient currently - and it works
    plen = []
    tasks.each_value { |x| plen << x.fetch(label.to_sym) }
    plen = plen.max_by(&:length).length.to_i unless plen.empty?
    grep = '' if grep.nil?
    tasks.each_pair do |k, v|
      if v[:text].downcase.include?(grep.downcase)
        msg = "#{v[label.to_sym].to_s.ljust(plen)} - " unless quiet
        puts "#{msg}#{v[:text]}"
      end
    end

    # Saving this mess for when I revisit metadata tags

    # tasks.each do |x|
    #   print("#{x[1].fetch(:text)} | #{x[1].fetch(label.to_sym)}")
    #   if x[1].length > 2
    #     print ' |'
    #     meta = x[1].reject { |key| key == :id || key == :text }
    #     meta_msg = []
    #     meta.each_pair { |a, b| meta_msg << " #{a}:#{b}," }
    #     print meta_msg.join.chop
    #   end
    #   print "\n"
    # end
    # tasks.each(&method(:pp))
  end

  def write(delete_if_empty = false)
    tasks = @tasks.reject { |_, v| v[:done] }
    done = @done
    filemap = { tasks: @name, done: ".#{@name}.done" }
    filemap.each_pair do |kind, filename|
      path = File.join(File.expand_path(@taskdir), filename)
      raise InvalidTaskfile if File.directory?(path)

      if kind === :tasks
        File.open(path.to_s, 'w') do |tfile|
          tasklines_from_tasks(tasks).each do |task|
            tfile.write(task)
          end
        end
      else
        File.open(path.to_s, 'w') do |tfile|
          tasklines_from_tasks(done).each do |task|
            tfile.write(task)
          end
        end
      end


    end
  end
end

# TODO print :default mixin?
opts = Slop.parse suppress_errors: true do |opt|
  progname = File.basename($0, File.extname($0))
  opt.banner  = "usage: #{progname} [-t DIR] [-l LIST] [options] [TEXT]"
  opt.string  '-e', '--edit',   'edit TASK to contain TEXT'
  opt.string  '-f', '--finish', 'mark TASK as finished'
  opt.string  '-r', '--remove', 'remove TASK'
  # TODO opt.string '--purge',  'purge finished tasks'

  opt.string  '-l',     '--list',            'act on LIST',
              default:  'tasks'
  opt.string  '-t',     '--task-dir',        'act on the lists in DIR',
              default: '.'
  opt.bool    '-d',     '--delete-if-empty', 'delete the task file if it becomes empty',
              default: false
  opt.string  '-g',     '--grep',            'print only tasks containing WORD'
  opt.bool    '-v',     '--verbose',         'print more detailed output (full task ids, etc)',
              default: false
  opt.bool    '-q',     '--quiet',           'print less detailed output (no task ids, etc)',
              default: false
  opt.bool    '--done',                      'list done tasks instead of unfinished ones',
              default: false
  opt.on      '--help' do
                puts opt
                exit
              end
end


begin
  text = opts.arguments.join(' ')
  td = TaskDict.new(opts[:'task-dir'], opts[:list])
  if opts[:finish]
    td.finish_task(opts[:finish])
    td.write(opts['delete-if-empty'.to_sym])
    exit 0
  elsif opts[:remove]
    td.remove_task(opts[:remove])
    td.write(opts['delete-if-empty'.to_sym])
    exit 0
  elsif opts[:edit]
    td.edit_task(opts[:edit], text)
    td.write(opts['delete-if-empty'.to_sym])
    td.print_list
    exit 0
  elsif !text.empty?
    td.add_task(text)
    td.write(opts['delete-if-empty'.to_sym])
    exit 0
  else
    if opts[:done]
      kind = 'done'
    else
      kind = 'tasks'
    end
    td.print_list(kind: kind, verbose: opts[:verbose], quiet: opts[:quiet], grep: opts[:grep])
  end
rescue AmbiguousPrefix => e
  puts "'#{e.message}' matches more than one task ID."
rescue UnknownPrefix => e
  puts "No tasks IDs match '#{e.message}.'"
rescue BadFile => e
  #puts "File not found: #{e.message}"
end
