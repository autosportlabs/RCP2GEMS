#!/usr/bin/python
#  Author:      Daniel Poulter  mrpilt@gmail.com
#  Script Name:   RCP_conv.py
#  Function:      Takes Race Capture Pro csv logs and converts them to a
#         GEMS Dlog99 compatible format, so you can then save logs in
#         Dlog99 into .srt files which can be opened by GEMS Data Analysis
#         or AEM Data Analysis.
#  Notes:   Thanks to John Freund for working out required format for GEMS in rccsv2gems.pl
# 			Max Value in GEMS CSV inport file is 2147483
#  Version:    1.0
#
# Changes:
#		V1.0
# 		Skip the start of the data until GPSSats value is >= num_of_sats (set to zero to skip nothing)
# 		Note: GPS dropout later in file will still be transfered
#		Uses the RCP Interval time for GEMS (not GPS timestamp, as this seems inconsistant)
#		Output filename is 'inputfilname'_GEMS.csv. Can be overridden by sepcifying another output_filename

import csv
import sys





def RCP_to_GEMS(filename, num_of_sats=0, output_filename = None):
	to_rads = 0.01745329251
	with open(filename, 'rb') as input_file:
		if not output_filename:
			output_filename = filename.split('.')[0] + '_GEMS.csv'
		with open(output_filename, 'wb') as output_file:
			reader = csv.reader(input_file, quoting=csv.QUOTE_NONNUMERIC)     #Reads all input as floats
			writer = csv.writer(output_file)

			#Example headers: Interval,Utc,Battery,AccelX,AccelY,AccelZ,Yaw,Pitch,Roll,Latitude,Longitude,Speed,Distance,GPSSats,LapCount,LapTime,Sector,SectorTime,PredTime
		 	header = []
		 	title_row = reader.next()
			for column in title_row:
				header.append(column.split("|")[0])

			try:
				GPSSats_index = header.index('GPSSats')
				Latitude_index = header.index('Latitude')
				Longitude_index = header.index('Longitude')
			except:
				GPSSats_index = 0
				Latitude_index = 0
				Longitude_index = 0

			writer.writerows([header])

			#Skip rows until a GPS fix occurs
			if GPSSats_index != 0:
				skipped = 0
				while True:
					try:
						if reader.next()[GPSSats_index] >= num_of_sats:
							print "%d lines skipped"%skipped
							break
						skipped += 1
					except ValueError:		#Illegal Character :- Continue on next line
						print "Warning: Illegal Character on row %d "%reader.line_num
						continue
					except Exception, e:	#All other exceptions
						print "Read Error : %s"%e
						return (False, e)


			#First row is handled differently, from here we get the start time and populate all blanks with 0.0
			first_row  = reader.next()
			start_time = int(first_row[0])
			start_time_gps = int(first_row[1])

			for i in range(len(first_row)):
				if first_row[i] == '':
					first_row[i] = 0.0

			first_row[0] = 0.0 															#Set time to zero
			first_row[1] = 0.0 															#Set GPS time to
			if GPSSats_index != 0:
				first_row[Longitude_index] = first_row[Longitude_index] * to_rads			#Convert to radians
				first_row[Latitude_index] = first_row[Latitude_index] * to_rads				#Convert to radians
			writer.writerows([first_row])												#Write to output
			previous_row = first_row

			while True: #Runs until exception occurs

				try:
					current_row  = reader.next()
				except StopIteration:	#Reached end of file
					return (True, output_filename)
				except ValueError:		#Illegal Character :- Continue on next line
					print "Warning: Illegal Character on row %d "%reader.line_num
					continue
				except Exception, e:	#All other exceptions
					print "Read Error : %s"%e
					return (False, e)

				current_row[0] = (int(current_row[0]) - start_time)/1000.0  				#Convert time
				current_row[1] = (int(current_row[1]) - start_time_gps)/1000.0  			#Convert time
				if GPSSats_index != 0:
					current_row[Longitude_index] = current_row[Longitude_index] * to_rads		#Convert to radians
					current_row[Latitude_index] = current_row[Latitude_index] * to_rads			#Convert to radians

				#If blanks found, populate with last known good value
				for i in range(len(current_row)):
					if current_row[i] == '':
						current_row[i] = previous_row[i]

				previous_row = current_row
				writer.writerows([current_row])



if __name__ == "__main__":
	if len(sys.argv) == 4:
		print RCP_to_GEMS(sys.argv[1], sys.argv[3], sys.argv[2])
	elif len(sys.argv) == 3:
		print RCP_to_GEMS(sys.argv[1], 0, sys.argv[2])
	elif len(sys.argv) == 2:
		print RCP_to_GEMS(sys.argv[1], 0)
	else:
		print "Usage: RCP_Conv.py INPUTFILENAME OUTPUTFILENAME MINSATS"
		print "-------------------------------------------------------"
		print "(Required) INPUTFILENAME - Your RCP .LOG file"
		print "(Optional) OUTPUTFILENAME - Desired output file. If not provided one will be created automatically"
		print "(Optional) MINSATS - The minimum number of GPS satellites required for valid data"



