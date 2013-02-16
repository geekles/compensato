class FileOp < ActiveRecord::Base
  # attr_accessible :title, :body

#Auto-mounts client drive by collecting "fdisk -l" output from system, then looking for the 
#line that contains "NTFS" and then iterates through to find the line that has the most 
#blocks which is most likely to be the main windows installation. After the drive is mounted
#it then creates a "Compensato" folder on the client drive if it doesn't exist
def self.mount_client_drive
	fdisk_list = %x(fdisk -l).split("\n")
	device_id = String.new
	most_blocks = 0

	if Dir.exist?("/media/compensato_client") == false
		Dir.mkdir("/media/compensato_client")
	end

	if Dir.entries("/media/compensato_client").size <= 2
		fdisk_list.each{|line|
			if line.include?("NTFS") and line.split[-3].to_i > most_blocks
				device_id = line[0..8]
			end
		}

		system("mount #{device_id} /media/compensato_client")
	end

	if Dir.exist?("/media/compensato_client/Compensato") == false
		Dir.mkdir("/media/compensato_client/Compensato")
	end
end

#Uses the system's "find" command to create a list of files maching the modified time given 
#then filters them for unwanted files and to make sure they match the appropriate extensions
def self.file_scan_20(entered_scan_days, extensions)
	full_file_list = %x(find /media/compensato_client/ -type f -mtime -#{entered_scan_days}).split("\n")
	lines_to_return = Array.new
	
	full_file_list.each{|line|	
		if check_for_garbage_file_names(line) == false and check_for_appropriate_file_type(line, extensions) == true
			lines_to_return << line.chomp
		end
	}
	
	return lines_to_return
end

def self.copy_user_data(copy_direction, customer_name)
	
	if copy_direction == "to_external"
		source_directory = "/media/customerdrive/Users"
		target_directory = "/media/ubuntu/TCGStorage/CustomerData/#{customer_name}"
	elsif copy_direction == "from_external"
		source_directory = "/media/ubuntu/TCGStorage/CustomerData/#{customer_name}"
		target_directory = "/media/customerdrive/TCG/customer_data"
	end
	
	system "mkdir -p #{target_directory} 2>/dev/null"
	
	if system "mkdir #{target_directory}/#{customer_name}"
		puts
		puts
		puts "Calculating original user folder size (This may take a little bit to calculate)..."
		
		original_users_directory_size = calculate_directory_size("#{source_directory}")
		destination_directory_size = 0
		
		system "clear"
		
		puts
		puts "The complete Users folder on this system totals:"
		puts
		puts "#{(original_users_directory_size.to_f / 1000000).round(2)}GB"
		
		puts
		print "Would you like to continue? (y/n):"
		continue_copy_prompt = gets.chomp
		system "clear"
		
		case continue_copy_prompt
			when "y", "Y"			
				puts	
				puts "Starting copy of user data to /CustomerData/#{customer_name} (This should copy at about 1GB/min)"
				
				puts
				puts "Copy started at #{Time.now.strftime("%I:%M%p")}"
				puts
				
				spawn "cp -a #{source_directory} #{target_directory}/#{customer_name}"
				
				percent_completed = 0
				
				until percent_completed.round == 100
					destination_directory_size = calculate_directory_size("#{target_directory}/#{customer_name}")
					
					percent_completed = calculate_complete_percentage(destination_directory_size, original_users_directory_size)
					print "  #{percent_completed.round}% #{(destination_directory_size.to_f / 1000000).round(2)}GB of #{(original_users_directory_size.to_f / 1000000).round(2)}GB complete \r"
				
					sleep 10
				end
				
				system "chown -R ubuntu #{target_directory}/#{customer_name}"
				
				system "clear"
				
				original_directory_file_count = count_number_of_files_in_directory("#{source_directory}")
				destination_directory_file_count = count_number_of_files_in_directory("#{target_directory}/#{customer_name}")
				
				puts
				puts
				puts "Please verify the original and copied directory sizes are the same:"
				puts
				
				puts "--   SOURCE     -- folder size: #{(original_users_directory_size.to_f / 1000000).round(2)}GB"
				puts "--   SOURCE     -- file count:  #{original_directory_file_count}"
				
				puts
				puts "-- DESTINATION  -- folder size: #{(destination_directory_size.to_f / 1000000).round(2)}GB"
				puts "-- DESTINATION  -- file count:  #{destination_directory_file_count}"
				
				puts
				print "Press [Enter] to continue..."
				gets.chomp
				system "clear"
			else
		end
	else
		system "clear"
		puts
		puts
		puts "************** THAT CUSTOMER NAME ALREADY EXISTS, TRY AGAIN **************"
	end
end

def self.check_for_garbage_file_names(file_string)
	garbage_strings = [".pf", "Windows/assembly/GAC/Microsoft.DirectX", "/Windows/assembly/NativeImages", 
						"/Windows/Microsoft.NET/assembly/GAC", "/Windows/winsxs/x86_microsoft"]
	
	garbage_strings.each{|gs|
		if file_string.downcase.include?(gs.downcase)
			return true
		end
	}
	
	return false
end

def self.check_for_appropriate_file_type(file_string, extensions)
	extensions.each{|e|
		if file_string.reverse[0..4].downcase.include?("#{e.reverse}.")
			return true
		end
	}
end

def self.create_final_scan_log(selected_paths, extensions)
	file_paths = selected_paths
	file_objects = Array.new
	final_scan_log = File.open("/media/compensato_client/Compensato/scanlog_#{Time.now}.txt", "w+")

	file_paths.each{|file_path|
		file = File.open(file_path, "r")
		file_objects << file
	}

	extensions.each{|extension|
		final_scan_log.puts "######################################################"
		final_scan_log.puts "####### .#{extension} files modified in the last XX days ######"
		final_scan_log.puts "######################################################"
		final_scan_log.puts
		final_scan_log.puts "       Modified at:       |       Path:"
		final_scan_log.puts "______________________________________________________"
		final_scan_log.puts

		file_objects.each{|file_object|
			if file_object.path.include?(".#{extension}")
				final_scan_log.puts "#{file_object.mtime} | #{file_object.path.gsub("/media/compensato_client", "")}"
			end
		}

		final_scan_log.puts
		final_scan_log.puts
	}

	final_scan_log.close
end

end
