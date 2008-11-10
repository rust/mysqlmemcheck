#!/usr/bin/env ruby

require 'optparse'
require 'pp'

KByte = 1024
MByte = 1024 * 1024
GByte = 1024 * 1024 * 1024

OVER_TEXT = [27].pack('C*') + '[31;1m' + 'Over!!' + [27].pack('C*') + '[m'
SAFE_TEXT = [27].pack('C*') + '[32;1m' + "Safe"   + [27].pack('C*') + '[m'

GLOBAL_BUFFERS = %w(
  key_buffer_size
  innodb_buffer_pool_size
  innodb_log_buffer_size
  innodb_additional_mem_pool_size
  net_buffer_length
).freeze

THREAD_BUFFERS = %w(
  sort_buffer_size
  myisam_sort_buffer_size
  read_buffer_size
  join_buffer_size
  read_rnd_buffer_size
).freeze

HEAP_LIMIT = %w(
  innodb_buffer_pool_size
  key_buffer_size
  sort_buffer_size
  read_buffer_size
  read_rnd_buffer_size
).freeze

INNODB_LOG_FILES = %w(
  innodb_buffer_pool_size
  innodb_log_files_in_group
).freeze

OTHER_VARIABLES = %w(
  max_connections
).freeze

REQUIRE_VARIABLES = [
  GLOBAL_BUFFERS,
  THREAD_BUFFERS,
  HEAP_LIMIT,
  INNODB_LOG_FILES,
  OTHER_VARIABLES
].flatten.sort.uniq.freeze

# read my.cnf variables
def read_my_variables(filename)
  myval = Hash.new
  mycnf     = nil
  in_mysqld = nil
  File.open(filename, "r") do |file|
    while line = file.gets
      if line =~ /^\[/
        mycnf = true
        if line =~ /^\[mysqld\]/
          in_mysqld = true
        else
          in_mysqld = nil
        end
      end
      next if mycnf and !in_mysqld

      line = line.chomp.gsub(/^\|\s+/, '')
      next if line =~ /^#/

      name, value = split(/[\s=|]+/)
      next unless value
      value = value.gsub(/\s*\|\s*$/, '')
      value = to_byte(value) if value =~ /[KMG]$/
      myval[name] = value
      if name =~ /buffer$/
        myval[name + '_size'] = value
      end
    end
  end

  myval
end

# validate read variables
def validate_my_variables(myval)
  missing = []
  REQUIRE_VARIABLES.each do |var_name|
    missing << var_name unless myval[var_name]
  end

  missing = missing.sort.uniq
  if missing.size > 0
    puts "[ABORT] missing variables:\n  " + missing.join("\n  ") + "\n\n"
    exit
  end
end

# Reports
def report_minimal_memory(myval)
  global_buffer_size = 0
  thread_buffer_size = 0
  minimal_memory = 0

  GLOBAL_BUFFERS.each do |params|
    global_buffer_size += myval[params].to_i
  end

  THREAD_BUFFERS.each do |params|
    thread_buffer_size += myval[params].to_i
  end

  minimal_memory = global_buffer_size + thread_buffer_size * myval["max_connections"].to_i
  total_memory = minimal_memory + to_byte($system_memory_size)

  puts <<END
[ minimal memory ]
ref: High Performance MySQL, Solving Memory Bottlenecks, p125

END

  puts "global buffers"
  GLOBAL_BUFFERS.each do |params|
    printf "  %-32s %12d  %12s\n", params, myval[params], to_unit(myval[params])
  end
  puts "\n"

  puts "thread buffers\n"
  THREAD_BUFFERS.each do |params|
    printf "  %-32s %12d  %12s\n", params, myval[params], to_unit(myval[params])
  end
  puts "\n"

  printf "%-34s %12d\n", 'max_connections', myval["max_connections"]
  puts "\n"

  printf "min_memory_needed = global_buffers + (thread_buffers * max_connections)
                  = %d + %d * %d
                  = %d (%s)\n",
  global_buffer_size,
  thread_buffer_size,
  myval["max_connections"],
  minimal_memory,
  to_unit(minimal_memory)
  puts "\n"

  puts "system memory size = #{$system_memory_size}\n\n"

  printf "total require memory = min_memory_needed + system_memory_size
                     = %d + %d
                     = %d (%s) %s\n\n",
  minimal_memory, to_byte($system_memory_size), total_memory, to_unit(total_memory),
  total_memory > to_byte($machine_momory_size) ? "> #{$machine_momory_size} (#{OVER_TEXT})" : "< #{$machine_momory_size} (#{SAFE_TEXT})"
end

def to_byte(val)
  return val unless val =~ /^(\d+)([KMG])$/
  num  = $1.to_i
  unit = $2

  case $2
  when 'G'
    num *= GByte
  when 'M'
    num *= MByte
  when 'K'
    num *= KByte
  else
    num = 0
  end

  num
end

def to_unit(num)
  base = 0
  unit = ''

  if num > GByte
    base = GByte
    unit = 'G'
  elsif num > MByte
    base = MByte
    unit = 'M'
  elsif num > KByte
    base = KByte
    unit = 'K'
  else
    base = 1
    unit = ''
  end

  sprintf("%.3f [#{unit}]", num/base.to_f)
end

# main
$machine_momory_size = "4G"
$system_memory_size  = "256M"
Version = "0.0.1"

OptionParser.new do |opt|
  opt.on('-h', '--help', 'Show this help.'){|v| puts opt; nil}
  opt.on('-m', '--memory=NUM', 'Server machine memory size.(Default: 4G)'){|v| $machine_momory_size = v}
  opt.on('-s', '--system=NUM', 'Server system memory size.(Default: 256M)'){|v| $system_memory_size = v}

  opt.parse!(ARGV)

  unless $mycnf_filename = ARGV.first
    puts opt
    exit 1
  end
end


@myval = read_my_variables($mycnf_filename)
validate_my_variables(@myval)

report_minimal_memory(@myval)
