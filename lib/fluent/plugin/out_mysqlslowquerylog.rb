# coding: utf-8

class Fluent::MySQLSlowQueryLogOutput < Fluent::Output
  Fluent::Plugin.register_output('mysqlslowquerylog', self)
  include Fluent::HandleTagNameMixin

  def configure(conf)
    super
    @slowlogs = {}

    if !@remove_tag_prefix && !@remove_tag_suffix && !@add_tag_prefix && !@add_tag_suffix
      raise ConfigError, "out_myslowquerylog: At least one of option, remove_tag_prefix, remove_tag_suffix, add_tag_prefix or add_tag_suffix is required to be set."
    end
  end

  def start
    super
  end

  def shutdown
    super
  end

  def emit(tag, es, chain)
    if !@slowlogs[:"#{tag}"].instance_of?(Array)
      @slowlogs[:"#{tag}"] = []
    end
    es.each do |time, record|
      concat_messages(tag, time, record)
    end

    chain.next
  end

  def concat_messages(tag, time, record)
    record.each do |key, value|
      if !value.upcase.start_with?('SET TIMESTAMP=') 
        @slowlogs[:"#{tag}"] << value
      end 
      if value.end_with?(';') && !value.upcase.start_with?('USE ', 'SET TIMESTAMP=')
        parse_message(tag, time)
      end
    end
  end

  REGEX1 = /^#? User\@Host:\s+(\S+)\s+\@\s+(\S+).*/
  REGEX15 = /^# Thread_id:\s+([0-9.]+)\s+Schema:\s+(\S+)\s+QC_hit:\s+(\S+).*/
  REGEX2 = /^# Query_time:\s+([0-9.]+)\s+Lock_time:\s+([0-9.]+)\s+Rows_sent:\s+([0-9.]+)\s+Rows_examined:\s+([0-9.]+).*/
  REGEX3 = /^# Rows_affected:\s+([0-9.]+)\s+Bytes_sent:\s+([0-9.]+).*/
  REGEX4 = /^# Full_scan:\s+(\S+)\s+Full_join:\s+(\S+)\s+Tmp_table:\s+(\S+)\s+Tmp_table_on_disk:\s+(\S+).*/
  REGEX5 = /^# Filesort:\s+(\S+)\s+Filesort_on_disk:\s+(\S+)\s+Merge_passes:\s+([0-9.]+)\s+Priority_queue:\s+(\S+).*/
  def parse_message(tag, time)
    record = {}
    date   = nil

    # Skip the message that is output when after flush-logs or restart mysqld.
    # e.g.) /usr/sbin/mysqld, Version: 5.5.28-0ubuntu0.12.04.2-log ((Ubuntu)). started with:
    begin
      message = @slowlogs[:"#{tag}"].shift
    end while !message.start_with?('#')

    if message.start_with?('# Time: ')
      date    = Time.parse(message[8..-1].strip)
      message = @slowlogs[:"#{tag}"].shift
    end

    if( ( message =~ REGEX1 ) != nil ) 
      record['user'] = $1
      record['host'] = $2
      message = @slowlogs[:"#{tag}"].shift
    end

    if( ( message =~ REGEX15 ) != nil )
      #record['r15']    = message
      record['thread_id']    = $1.to_i
      record['schema']     = $2
      record['qc_hit']     = $3
    
      message = @slowlogs[:"#{tag}"].shift
    end

    if( ( message =~ REGEX2 ) != nil )
      #record['r2']    = message
      record['query_time']    = $1.to_f
      record['lock_time']     = $2.to_f
      record['rows_sent']     = $3.to_i
      record['rows_examined'] = $4.to_i
    
      message = @slowlogs[:"#{tag}"].shift
    end

    if( ( message =~ REGEX3 ) != nil )
    #record['r3']    = message
      record['rows_affected']    = $1.to_i
      record['bytes_sent']     = $2.to_i

      message = @slowlogs[:"#{tag}"].shift
    end

    if( ( message =~ REGEX4 ) != nil )
      #record['r4']    = message
      record['full_scan']    = $1
      record['full_join']     = $2
      record['temp_table']     = $3
      record['temp_table_on_disk'] = $4

      message = @slowlogs[:"#{tag}"].shift
    end

    if( ( message =~ REGEX5 ) != nil )
      #record['r5']    = message
      record['filesort']    = $1
      record['filesort_on_disk']  = $2
      record['merge_passes']     = $3.to_i
      record['priority_queue'] = $4
    end

    record['sql'] = @slowlogs[:"#{tag}"].map {|m| m.strip if !m.strip.start_with?('#') }.join(' ').strip

    time = date.to_i if date
    flush_emit(tag, time, record)
  end

  def flush_emit(tag, time, record)
    @slowlogs[:"#{tag}"].clear
    _tag = tag.clone
    filter_record(_tag, time, record)
    if tag != _tag
      router.emit(_tag, time, record)
    else
      $log.warn "Can not emit message because the tag has not changed. Dropped record #{record}"
    end
  end
end
