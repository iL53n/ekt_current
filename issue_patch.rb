module RedmineMeetingRoomCalendar
  module Patches
    module IssuePatch
      def self.included(base)
        base.class_eval do
          unloadable

          validate :checking_issue

          protected

          def checking_issue
            @tracker_id = Setting['plugin_redmine_meeting_room_calendar']['tracker_id']
            @project_id = Setting['plugin_redmine_meeting_room_calendar']['project_id']
            @project_ids = Setting['plugin_redmine_meeting_room_calendar']['project_ids'] || []

            unless @project_id == nil || @project_id == 0 ||  @project_id == '0' || @project_id == ''
              @project_ids = @project_ids + [@project_id]
              Setting['plugin_redmine_meeting_room_calendar']['project_ids'] = @project_ids
            else
              @project_id = @project_ids[0]
            end

            if @project_ids.include?(self.project_id.to_s)
              @overlap = false
              @overlap_user = false
              err = 0

              @project_id_ill = Setting['plugin_redmine_meeting_room_calendar']['project_id_ill']
              @project_ids_ill = Setting['plugin_redmine_meeting_room_calendar']['project_ids_ill'] || []

              unless @project_id_ill == nil || @project_id_ill == 0 ||  @project_id_ill == '0' || @project_id_ill == ''
                @project_ids_ill = @project_ids_ill + [@project_id_ill]
                Setting['plugin_redmine_meeting_room_calendar']['project_ids'] = @project_ids_ill
              else
                @project_id_ill = @project_ids_ill[0]
              end

              if self[:due_date].to_s == '' || self[:due_date].to_s == '0' || self[:due_date].to_s == 'nil'
                errors.add :due_date, 'Дата окончания не может быть пустой!'
                err = 1
                return
              end

              if self[:due_date].to_s != self[:start_date].to_s
                errors.add :due_date, 'В совещаниях дата окончания должна совпадать с начальной датой!'
                err = 1
                return
              end

              room = 0
              start_time = 0
              end_time = 0
              ucha = 0

              @custom_field_id_room = Setting['plugin_redmine_meeting_room_calendar']['custom_field_id_room']
              @custom_field_id_start = Setting['plugin_redmine_meeting_room_calendar']['custom_field_id_start']
              @custom_field_id_end = Setting['plugin_redmine_meeting_room_calendar']['custom_field_id_end']
              @custom_field_id_uchastniki = Setting['plugin_redmine_meeting_room_calendar']['custom_field_id_uchastniki']

              self.custom_field_values.length.times do |i|
                a = self.custom_field_values[i].custom_field.name
                b = IssueCustomField.find(@custom_field_id_room).name
                c = IssueCustomField.find(@custom_field_id_start).name
                d = IssueCustomField.find(@custom_field_id_end).name
                e = IssueCustomField.find(@custom_field_id_uchastniki).name

                if a == b then
                  room = i
                elsif a == c
                  start_time = i
                elsif a == d
                  end_time = i
                elsif a == e
                  ucha = i
                end
              end

              if self.custom_field_values[start_time].to_s != '' && self.custom_field_values[end_time].to_s != ''
                if Time.parse(self.custom_field_values[start_time].to_s) >= Time.parse(self.custom_field_values[end_time].to_s)
                  errors.add self.custom_field_values[start_time].to_s, 'Время начала больше времени окончания!'
                  err = 1
                  return
                end
              else
                err = 1
              end


              if err == 0 then
                ###### ПРОВЕРКА ЗАНЯТОСТИ ПОМЕЩЕНИЙ ######

                @issues = Issue.find_by_sql("select *, d1.value as d1_value, d2.value as d2_value, d3.value as d3_value
                         from issues u
                         INNER JOIN custom_values d1 ON d1.custom_field_id=(#{@custom_field_id_room})
                         INNER JOIN custom_values d2 ON d2.custom_field_id=(#{@custom_field_id_start})
                         INNER JOIN custom_values d3 ON d3.custom_field_id=(#{@custom_field_id_end})
                         where (project_id in (#{@project_ids.join(",")}))
                         AND (u.id <> '#{self[:id].to_s}')
                         AND (start_date >= '#{self[:start_date].to_s}')
                         AND (due_date <= '#{self[:due_date].to_s}')
                         AND (d1.value = '#{self.custom_field_values[room].to_s}')
                         AND (d1.customized_id = u.id)
                         AND (d2.customized_id = u.id)
                         AND (d3.customized_id = u.id);")

                @issues.length.times do |i|
                  startO = @issues[i].d2_value
                  endO = @issues[i].d3_value
                  startN = self.custom_field_values[start_time].to_s
                  endN = self.custom_field_values[end_time].to_s

                  if startO == startN then
                    @overlap = true
                  elsif endO == endN then
                    @overlap = true
                  elsif (startO >= startN) && (endO <= endN) then
                    @overlap = true
                  elsif (startO < startN) && (endO > startN) then
                    @overlap = true
                  elsif (startO < endN) && (endO > endN) then
                    @overlap = true
                  end

                  if @overlap == true
                    err = self.custom_field_values[room].to_s
                    errors.add err, "#{err} --> уже забронирована!"
                    return false
                  end
                end

                ###### ПРОВЕРКА ЗАНЯТОСТИ СОТРУДНИКОВ В ДРУГИХ СОВЕЩАНИЯХ ######

                if @overlap == false
                  @issues = Issue.find_by_sql("select *, d2.value as d2_value, d3.value as d3_value , d4.value as d4_value
                         from issues u
                         INNER JOIN custom_values d2 ON d2.custom_field_id=(#{@custom_field_id_start})
                         INNER JOIN custom_values d3 ON d3.custom_field_id=(#{@custom_field_id_end})
                         INNER JOIN custom_values d4 ON d4.custom_field_id=(#{@custom_field_id_uchastniki})
                         where (project_id in (#{@project_ids.join(",")}))
                         AND (u.id <> '#{self[:id].to_s}')
                         AND (start_date >= '#{self[:start_date].to_s}')
                         AND (due_date <= '#{self[:due_date].to_s}')
                         AND (d2.customized_id = u.id)
                         AND (d3.customized_id = u.id)
                         AND (d4.customized_id = u.id);")

                  a = self.custom_field_values[ucha]
                  b = a.to_s
                  b = b.gsub! '"' , ''
                  b = b.gsub! '[' , ''
                  b = b.gsub! ']' , ''
                  c = 0
                  if b.include? ','
                    b = b.gsub! ' ' , ''
                    s = b.split(",")
                    c = 1
                  else
                    s = b
                    c = 0
                  end

                  @issues.length.times do |i|
                    if @issues[i].d2_value==self.custom_field_values[start_time].to_s then
                      if c == 1
                        for k in s do
                          if @issues[i].d4_value == k then
                            busy_message(k)
                          end
                        end
                      else
                        if @issues[i].d4_value == s then
                          busy_message(s)
                        end
                      end

                    elsif @issues[i].d3_value==self.custom_field_values[end_time].to_s then
                      if c == 1
                        for k in s do
                          if @issues[i].d4_value == k then
                            busy_message(k)
                          end
                        end
                      else
                        if @issues[i].d4_value == s then
                          busy_message(s)
                        end
                      end
                    elsif (@issues[i].d2_value>=self.custom_field_values[start_time].to_s) && (@issues[i].d3_value<=self.custom_field_values[end_time].to_s) then
                      if c == 1
                        for k in s do
                          if @issues[i].d4_value == k then
                            busy_message(k)
                          end
                        end
                      else
                        if @issues[i].d4_value == s then
                          busy_message(s)
                        end
                      end
                    elsif (@issues[i].d2_value < self.custom_field_values[start_time].to_s) && (@issues[i].d3_value > self.custom_field_values[start_time].to_s) then
                      if c == 1
                        for k in s do
                          if @issues[i].d4_value == k then
                            busy_message(k)
                          end
                        end
                      else
                        if @issues[i].d4_value == s then
                          busy_message(s)
                        end
                      end
                    elsif (@issues[i].d2_value < self.custom_field_values[end_time].to_s) && (@issues[i].d3_value > self.custom_field_values[end_time].to_s) then
                      if c == 1
                        for k in s do
                          if @issues[i].d4_value == k then
                            busy_message(k)
                          end
                        end
                      else
                        if @issues[i].d4_value == s then
                          busy_message(s)
                        end
                      end
                    end

                    def busy_message(user)
                      err = User.find(user).to_s
                      errors.add err, "#{err} --> занят(а) на другой встрече!"
                      @overlap_user = true
                    end
                  end

                  ###### ПРОВЕРКА ОТСУТСТВИЙ ######

                  @issues = Issue.find_by_sql("select *, d2.value as d2_value, d3.value as d3_value , d4.value as d4_value
                         from issues u
                         INNER JOIN custom_values d2 ON d2.custom_field_id=(#{@custom_field_id_start})
                         INNER JOIN custom_values d3 ON d3.custom_field_id=(#{@custom_field_id_end})
                         INNER JOIN custom_values d4 ON d4.custom_field_id=(#{@custom_field_id_uchastniki})
                         where (project_id in (#{@project_ids_ill}))
                         AND (start_date >= '#{(self[:start_date] - 14).to_s}')
                         AND (due_date <= '#{(self[:start_date] + 14).to_s}')
                         AND (d2.customized_id = u.id)
                         AND (d3.customized_id = u.id)
                         AND (d4.customized_id = u.id);")
                  a = self.custom_field_values[ucha]

                  b = a.to_s
                  b = b.gsub! '"' , ''
                  b = b.gsub! '[' , ''
                  b = b.gsub! ']' , ''
                  c = 0

                  if b.include? ','
                    b = b.gsub! ' ' , ''
                    s = b.split(",")
                    c = 1
                  else
                    s = b
                    c = 0
                  end

                  @new_start_date = self.start_date.to_s
                  @new_due_date = self.due_date.to_s
                  @new_start_time = self.custom_field_values[start_time].to_s
                  @new_end_time = self.custom_field_values[end_time].to_s

                  @issues.length.times do |i|
                    old_start_date = @issues[i].start_date.to_s
                    old_due_date = @issues[i].due_date.to_s
                    old_start_time = @issues[i].d2_value
                    old_end_time = @issues[i].d3_value
                    uchastnik = @issues[i].d4_value

                    ##### если совещ выпадает внутри отсутствт на несколько дней #####
                    if (old_start_date < @new_start_date) &&
                        (old_due_date > @new_due_date) then
                      if c == 1
                        for k in s do
                          if uchastnik == k then
                            absence_massage(k)
                          end
                        end
                      else
                        if uchastnik == s then
                          absence_massage(s)
                        end
                      end

                      ##### внутри дня #####
                    elsif (old_start_date == @new_start_date) &&
                        (old_due_date == @new_due_date) &&
                        (old_start_time < @new_end_time) &&
                        (old_end_time > @new_start_time) then
                      if c == 1
                        for k in s do
                          if uchastnik == k then
                            absence_massage(k)
                          end
                        end
                      else
                        if uchastnik == s then
                          absence_massage(s)
                        end
                      end

                      ##### если отсутствие больше дня + имеет время начала и время окончания #####
                    elsif (old_start_date != old_due_date) then
                      if (old_due_date == @new_due_date) && (old_end_time > @new_start_time) then
                        if c == 1
                          for k in s do
                            if uchastnik == k then
                              absence_massage(k)
                            end
                          end
                        else
                          if uchastnik == s then
                            absence_massage(s)
                          end
                        end
                      elsif (old_start_date == @new_start_date) && (old_start_time < @new_end_time) then
                        if c == 1
                          for k in s do
                            if uchastnik == k then
                              absence_massage(k)
                            end
                          end
                        else
                          if uchastnik == s then
                            absence_massage(s)
                          end
                        end
                      end
                    end
                  end

                  def absence_massage(user)
                    err = User.find(user).to_s
                    errors.add err, "#{err} --> будет отсутствовать!"
                    return false
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
