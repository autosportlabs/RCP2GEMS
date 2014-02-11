#!/usr/bin/perl

##  Author:		John Freund  jpf11@cornell.edu
##  Script Name:	rccsv2gems.pl
##  Function:		Takes Race Capture Pro (v1.13) csv logs and converts them to a
##			GEMS Dlog99 compatible format, so you can then save logs in
##			Dlog99 into .srt files which can be opened by GEMS Data Analysis
##			or AEM Data Analysis.
##  Notes:		Thanks to neoraptor on the autosportlabs.org forums for
##			providing the format!
##  Version:		1.6
##
##  Changes:		1.6 - Added time interpolation.  Found that Dlog99 was dropping data
##				when data points had the same time values, which they would
##				as this script was setting empty time values to the last known
##				good time value.  To prevent the dropping I added a function
##				that interpolates time for data points between logged time
##				and sets the interpolated time values in the output.	
##			1.5 - Removed second tag_junk_lines function call from main as it 	
##				was redundant.  Added options for new parameters mingps and
##				disable-gps-cleanup.  "--mingps=X" sets the minimum
##				number of gps satellites required for gps data to be valid, 
##				defaults to 4.  "--disable-gps-cleanup" will disable cleaning up
##				by the data (defaults to false) and switch pre-cleanup to setting
##				all gps values prior to the first good set to the same as the
##				first good set.  Added lots of output to the
##				various data processing functions to indicate their status.
##				Enabled the gps lat/long conversion from degrees to radians
##				to make AEM/GEMS DA setup more seamless since they expect 
##				radians by default.
##			1.4 - Fixed an issue with how we fill in the blanks.  We were filling
##				in the blanks with last known good values, including "good" 
##				values from lines tagged for removal.  Changed to ignore those
##				lines so values from them don't corrupt the rest of the data. 	
##			1.3 - Added comments.  Changed junk character handling from setting
##				values to prior "good" values to instead just delete the
##				offending lines.  Also changed ctrl M stripping to be all 
##				elements as random ^M were screwing up other text matches. 
##				Moved the ^M stripping to earlier in the pipeline too.	
##			1.2 - Found that AEM/GEMS DA had issues with automatically
##				figuring out the track layout with how I was cleaning
##				up gps data.  For any missing data in the beginning of the
##				file I was entering "0.000" up until the data starts showing
##				up (after which any missing data is filled with the last 
##				known data).  This is a problem if all your gps data isn't 
##				around 0.000,0.000 as your data goes from that coordinate
##				to whatever the first real lat/long you have in your data. 
##				When AEM/GEMS DA reads the initial 0, it uses that to figure
##				out along with your other gps data how to draw the track 
##				and basically your line starts at 0,0 and goes immediately to
##				your first coordinate and continues on, and the track scales
##				WAY out (unless you happened to be logging data around 0,0).
##				My fix was basically to wipe any data before the first real
##				GPS coordinates.
##			1.1 - Added code to zero_start_time function that handles time
##				rollover at midnight.  Not a complete catch as to make
##				things simpler I assume the log will end before 10am 
##				the next day.  Also fixes time conversion issues for
##				times earlier than 10am as the values did not have
##				leading zeroes (i.e. 00 or 01-09 for hour) by and thus
##				the function I was using for time conversion to epoch
##				time was failing.  I just pad some zeroes in front 
##				right before the conversion, and then I add 86400 secs
##				if we're rolled past midnight.
##				Also got rid of the fill_in_the_blanks function by 
##				rolling it into the zero_start_time function.
##			1.0	initial release
##
##  Usage:		rccsv2gems.pl INPUTFILENAME OUTPUTFILENAME --minsats=X --disable-gps-cleanup
##			(optional)  --minsats=X where X is the minimum number of gps satellites required 
##				for valid data (sets lat/long to null if GpsSats value is less than min)
##				Default is 4.
##			(optional)  --disable-gps-cleanup disables the cleanup per the GpsSats value.
##					Useful when you don't care or don't have the GpsSats column logged.

use strict;
use Text::CSV;
use Scalar::Util 'looks_like_number';
use Time::Piece;
use POSIX qw(ceil floor);

my $script_name="rccsv2gems.pl";
my $version="1.0";

my $file = shift(@ARGV); #takes parameter of RaceCapture Pro csv log to modify for GEMS
my $output = shift(@ARGV);
my $arg3 = shift(@ARGV);
my $arg4 = shift(@ARGV);

my $minimum_sats=4;  #default minimum number of gps satellites required
my $disable_gps_cleanup="false"; #gps cleanup is enabled by default


## read in parameters
if (!defined $file) {
	die "Error - No input file specified.  Terminating.\n";
}

if (!defined $output) {
	die "Error - No output file specified.  Terminating\n";
}

if ( $arg3 ) {
	if ( $arg3 =~ /\-\-minsats\=/ ) {
		$minimum_sats = (split( /\=/ ,$arg3 ))[1];
	}
	if ( $arg3 =~ /\-\-disable\-gps\-cleanup/ ) {
		$disable_gps_cleanup="true";		
	}
}

if ( $arg4 ) {
        if ( $arg4 =~ /\-\-minsats\=/ ) {
                $minimum_sats= (split( /\=/ ,$arg4 ))[1];
        }
        if ( $arg4 =~ /\-\-disable\-gps\-cleanup/ ) {
                $disable_gps_cleanup="true";
        }
}

## Functions
sub modify_headers {
	my @array=@_;
	print "Initiating Header Cleanup - Cleans up column headers.\n";
	for(my $i = 0; $i <= $#{$array[0]} ; $i++){
		my @element = split (/\|/, $array[0][$i]);
		$array[0][$i]=$element[0];	
		$array[0][$i] =~ s/\"//g; 
	}
	print "Header Cleanup Completed Successfully!\n";
	print "\n";
}

sub move_time_to_first_column {
	my @array=@_;
	my $timecolumn="null";
	print "Initiating Moving Time Column to Front - Moves the Time column to the first column.\n";
	for(my $i = 0; $i <= $#{$array[0]} ; $i++){
		if ( $array[0][$i] =~ /Time/ ) {
			$timecolumn = $i;
		}
	}
	if ($timecolumn == "null"){
		die "Error - Time column is not present in input csv.  Terminating\n";
	}
	for(my $i = 0; $i <= $#array; $i++){
		my $swap = $array[$i][0];
		$array[$i][0] = $array[$i][$timecolumn];
		$array[$i][$timecolumn] = $swap;
	}
	print "Time Column to Front Completed Successfully!\n";
	print "\n";
}

sub convert_time {
	my $time=$_[0];
	(my $HHMMSS, my $ms) = split(/\./,$time);
	my $date = Time::Piece->strptime($HHMMSS, "%H%M%S");
	my $epoch_time = $date->epoch;
	my $newtime = "$epoch_time.$ms";
	return $newtime;
}

sub zero_start_time {  #resets the time columns value to start at 0 by subtracting first value, also covers for going over midnight somewhat
	my @array=@_;
	my $base_time="null";
	my $pastmidnight="0";
	my $last_time="0";
	my $remove_column=($#{$array[0]} + 1);
	print "Initiating Time Adjustment - Sets all times relative to the start time and converts times to seconds.\n";
	for(my $i = 1; $i <= $#array ; $i++){
		if ($array[$i][$remove_column] ne "remove"){
		if (( looks_like_number($array[$i][0]) != 0 ) && ( $last_time > 230000 ) && ( $array[$i][0] < 100000 )){
			$pastmidnight="1";
		}
		if (( looks_like_number($array[$i][0]) != 0 ) && ($base_time == "null" )) {
			$last_time=$array[$i][0];
			$base_time=convert_time($array[$i][0]);
			$array[$i][0]="0.000";
			
		}
		else {
			if ( looks_like_number($array[$i][0]) != 0 ) {
				if ( $array[$i][0] < 100000) {
					if ( $array[$i][0] < 10 ) {
							$array[$i][0]="00000$array[$i][0]";
					} elsif ( $array[$i][0] < 100 ) {
                                                        $array[$i][0]="0000$array[$i][0]";
					} elsif ( $array[$i][0] < 1000 ) {
                                                        $array[$i][0]="000$array[$i][0]";
                                        } elsif ( $array[$i][0] < 10000 ) {
                                                        $array[$i][0]="00$array[$i][0]";
                                        } else { $array[$i][0] = "0$array[$i][0]";
					}
					
				}
				my $converted_time = convert_time($array[$i][0]);
				if ( $pastmidnight == "1" ) {
					$converted_time+=86400;
				}	
				my $diff=($converted_time - $base_time);
				$array[$i][0]=sprintf"%.3f",$diff;
			}
		}
		}
	}
	if ($base_time == "null"){
		die "Error - No time values were present.  Terminating.\n";
	}
	print "Time Adjustment Completed Successfully!\n";
	print "\n";
}

sub strip_ctrlm {
	my @array=@_;
	for(my $i = 0; $i <= $#array ; $i++){
		for(my $j = 0; $j <= $#{$array[0]} ; $j++){
			$array[$i][$j] =~ s/\r//g;	
		}
	}
}


sub fill_in_the_blanks { # fills in missing data with last known good data.  Ignores lines tagged for removal.
	my @array = @_;
	my @line = @{ $array[1] };
	my $remove_column=($#{$array[0]} + 1);
	print "Initiating Filling in the Blanks - Filling in empty data values with last known good value to make AEM/GEMS DA happy.\n";
	for(my $i = 1; $i <= $#array ; $i++){
		if ( $array[$i][$remove_column] ne "remove" ) {
			for(my $j = 0; $j <= $#{$array[0]} ; $j++){
				if ( looks_like_number($array[$i][$j]) == "0" ) {
					if ( looks_like_number($line[$j]) == "0" ) {
						$line[$j]="0.000";
					}	
					$array[$i][$j]="$line[$j]";
				}
				else {
					$line[$j]=$array[$i][$j];
				}
			}
		}
	}
	print "Filling in the Blanks Completed Successfully!\n";
	print "\n";

}

sub convert_gpsdegrees_to_radians {
	my @array = @_;
        my $lat_col="null";
	my $long_col="null";
	my $radian_conv="0.01745329251";
	print "Initializing GPS Degrees to Radians - Converts Lat/Long values from Degrees to Radians (which is default for AEM/GEMS DA).\n";
        for(my $i = 0; $i <= $#{$array[0]} ; $i++){
                if ( $array[0][$i] =~ /Longitude/ ) {
                        $long_col = $i;
                }
		if ( $array[0][$i] =~ /Latitude/ ) {
			$lat_col = $i;
		}
        }
        if ($long_col == "null"){
                die "Error - Longitude column is not present in input csv.  Terminating.\n";
        }
	if ($lat_col == "null"){
		die "Error - Latitude column is not present in input csv.  Terminating\n";
	}
	for(my $i = 1; $i <= $#array ; $i++){
		$array[$i][$long_col] = sprintf"%.13f",($array[$i][$long_col] * $radian_conv);
		$array[$i][$lat_col] = sprintf"%.13f",($array[$i][$lat_col] * $radian_conv);
	}
	print "GPS Degrees to Radians Completed Successfully!\n";
	print "\n";
}

sub tag_pre_gps_data { #tags data before the gps data shows up.  no gps data screws up track setup in GEMS DA. must be run before fill_in_the_blanks
        my @array = @_;
        my $lat_col="null";
        my $long_col="null";
	my $remove_column=($#{$array[0]} + 1);
	print "Initiating Pre-GPS Cleanup - removing all data before the first GPS entries.\n";
	for(my $i = 0; $i <= $#{$array[0]} ; $i++){
		if ( $array[0][$i] =~ /Longitude/ ) {
                        $long_col = $i;
                }
                if ( $array[0][$i] =~ /Latitude/ ) {
                        $lat_col = $i;
                }
        }
	my $i=1;
	while ((looks_like_number($array[$i][$long_col]) == 0) || (looks_like_number($array[$i][$lat_col]) == 0) || (($array[$i][$long_col] == 0 ) && ($array[$i][$lat_col] == 0))) {
		print "line $i, latitude is \"$array[$i][$lat_col]\", longitude is \"$array[$i][$long_col]\", erroneous values, tagging line for removal\n";
		$array[$i][$remove_column]="remove";
		$i++;
	}
	print "Found first line of valid gps data in line $i, latitude is \"$array[$i][$lat_col]\", longitude is \"$array[$i][$long_col]\".\n";
	print "Pre-GPS Cleanup Completed Successfully!\n";
	print "\n";
}

sub tag_junk_lines { #looks for non-numerical characters in the data and tags them for removal, needed for successful import into Dlog99
	my @array = @_;
	my $remove_column=($#{$array[0]} + 1);
	my $remove_line;
	print "Initiating Junk Line Removal Tagging - looking for lines with non-numerical data and tagging for removal during file output.\n";
	for(my $i = 1; $i <= $#array ; $i++){
		$remove_line="false";
		for(my $j = 0; $j <= $#{$array[0]} ; $j++){	
			if (( looks_like_number($array[$i][$j]) == 0 ) && ( $array[$i][$j] ne "" )) {
				print "line $i, element $j, value is $array[$i][$j], has invalid characters, removing\n";
				$remove_line="true";	
			}
		}
		if ( $remove_line eq "true" ) {
			print "Tagging line $i for remove!\n";
			$array[$i][$remove_column]="remove";
		}
	}
	print "Junk Line Removal Tagging Completed Successfully!\n";
	print "\n";

}

sub clean_gps_for_sats { # processes data removing any lines where GPS Sats are less than 4. Uses the global minimum_sats variable. Ignores lines tagged for removal.
	my @array = @_;
	my $gpssats_column;
	my $lat_column;
	my $long_column;
	my $remove_column=($#{$array[0]} + 1);
	print "Initiating GPS Cleanup - Removing lat/long when GpsSats is less than minimum of $minimum_sats:\n";
	for(my $i = 0; $i <= $#{$array[0]} ; $i++){
		if ( $array[0][$i] =~ /GpsSats/ ) {
			$gpssats_column="$i";
		}
		if ( $array[0][$i] =~ /Latitude/ ) {
                        $lat_column="$i";
                }
		if ( $array[0][$i] =~ /Longitude/ ) {
                        $long_column="$i";
                }
			
	}
	if (!defined $gpssats_column) {
		die "Error - GPS Processing enabled but no GpsSats column present in data.  Try --disable-gps-cleanup option.  Terminating.\n";
	}
	for(my $i = 1; $i <= $#array ; $i++){
		if ($array[$i][$remove_column] ne "remove") {
			if ((defined $array[$i][$gpssats_column]) && ($array[$i][$gpssats_column] < $minimum_sats) && (looks_like_number($array[$i][$gpssats_column]) > 0)) {
				print "line $i, GpsSats is $array[$i][$gpssats_column] which is less than the minimum sats of $minimum_sats, setting lat and long to null\n";
				$array[$i][$lat_column]="";
				$array[$i][$long_column]="";
			}
		}
	}
	print "GPS Cleanup Completed Successfully!\n";
	print "\n";
}

sub init_pre_gps_data { # finds the first numerical and non-zero lat/long values and then sets all prior lat/long to match.  Basically cleans up gps data until real gps data shows.  Needed because if you set pre-gps lat/long to zero you get weird rounding when going through Dlog99->AEM DA resulting in loss of gps resolution
        my @array = @_;
        my $lat_col="null";
        my $long_col="null";
        my $remove_column=($#{$array[0]} + 1);
        print "Initiating Pre-GPS initialization - Finds the first real gps lat/long values then sets all prior lat/long to match.\n";
        for(my $i = 0; $i <= $#{$array[0]} ; $i++){
                if ( $array[0][$i] =~ /Longitude/ ) {
                        $long_col = $i;
                }
                if ( $array[0][$i] =~ /Latitude/ ) {
                        $lat_col = $i;
                }
        }
        my $i=1;
        while ((((looks_like_number($array[$i][$long_col]) == 0) || (looks_like_number($array[$i][$lat_col]) == 0) || (($array[$i][$long_col] == 0 ) && ($array[$i][$lat_col] == 0)) || ($array[$i][$remove_column] eq "remove"))) && ($i <= $#array)) {
                $i++;
        }
	if ($i > $#array) {
		print "Did not find any valid gps data!\n";
	}
	else {
	        print "Found first line of valid gps data in line $i, latitude is \"$array[$i][$lat_col]\", longitude is \"$array[$i][$long_col]\".\n";
		print "Setting all lat/long data prior to line $i to \"$array[$i][$lat_col],$array[$i][$long_col]\".\n";
		for(my $x = 1; $x <= $i ; $x++){
			$array[$x][$lat_col]=$array[$i][$lat_col];
			$array[$x][$long_col]=$array[$i][$long_col];
		}
	}
        print "Pre-GPS Cleanup Completed Successfully!\n";
        print "\n";	
}

sub interpolate_time { #interpolates time data for lines between time changes so Dlog99 doesn't drop data when time values are the same
	my @array=@_;
	print "Initiating Time Interpolation - spaces out time measurements so Dlog99 doesn't drop data points for lines with the same time\n";
	my $remove_column=($#{$array[0]} + 1);	
	for(my $i = 1; $i <= $#array ; $i++){
		if (($array[$i][$remove_column] ne "remove") || (($i+1) > $#array)) { # ignore lines tagged for removal and stop if we're at the end
			my $current_time=$array[$i][0];
			my $next_time_line=$i;
			my $num_lines=0;
			while ((($current_time == $array[$next_time_line][0]) || ($array[$next_time_line][$remove_column] eq "remove")) && ($next_time_line < $#array)) { 
				$next_time_line++;
				if ($array[$next_time_line][0] ne "remove") {
					$num_lines++;		
				}
			}
				
			if ($num_lines > 1) {
				my $diff= (($array[$next_time_line][0] - $array[$i][0]) / $num_lines);
				my $j;
				if ($next_time_line == $#array) {
					for($j = ($i+1); $j <= $next_time_line; $j++) {
                                                $array[$j][0] = sprintf"%.3f",($array[$j - 1][0] + $diff);
					}
				}
				else {
					for($j = ($i+1); $j < $next_time_line; $j++) {
						$array[$j][0] = sprintf"%.3f",($array[$j - 1][0] + $diff);	
					}
				}
				$i=($next_time_line - 1); # step forward in the data to the next time
			}
		}
	}
	print "Time Interpolation Completed Successfully!\n";
	print "\n";
}
	

sub main {
	my @data;
	my $csv = Text::CSV->new;
	my $input="$file";
	my $output="$output";
	my $num_lines_removed=0;

	print "$script_name - Race Capture Pro CSV to GEMS DA conversion utility v$version\n\n";
	print "\n";
	print "Filtering data for a minimum of $minimum_sats GPS satellites.\n";
	if ($disable_gps_cleanup eq "true") {
		print "Disabling clean-up of GPS (if your data has bad gps data it's up to you to figure out how to get your track to draw properly in AEM/GEMS Data Analysis).\n";
	}
	print "\n";
	print "Initiating conversion...\n";
	

	open(INFILE,$input) || die "Can't open file $input";
	open(OUTFILE,">$output") || die "FATAL - Can't open file $output";

	my $i=0;
	while (<INFILE>) {
		chomp;
		if ($i == 0) {
			push @data, [split /,/];
		}
		else {  #Now to deal with the data I want to keep
			if($csv->parse($_)) {       #checks to see if data exists in $_ and parses it if it does
				$i++;
				my @fields=$csv->fields;  # puts the values from each field in an array
				push @data, [ @fields ];
				my $elements=@fields;     #gets the number of elements in the array
			}
		}
	}

	strip_ctrlm(@data);
        modify_headers(@data);
        move_time_to_first_column(@data);
	tag_junk_lines(@data);
	if ($disable_gps_cleanup ne "true") {
		clean_gps_for_sats(@data);
		tag_pre_gps_data(@data);
	}
	else {
		init_pre_gps_data(@data);	
	}
        zero_start_time(@data);
	fill_in_the_blanks(@data);
	interpolate_time(@data);
	convert_gpsdegrees_to_radians(@data);

	my $remove_column=($#{$data[0]} + 1);
        for(my $i = 0; $i <= $#data; $i++){
		if ( $data[$i][$remove_column] ne "remove" ){  #only print lines not tagged with "remove" in last column
			for(my $j = 0; $j <= $#{$data[0]} ; $j++){
				if ($#{$data[0]} == $j){
					print OUTFILE "$data[$i][$j]";
				}
				else {
					print OUTFILE "$data[$i][$j],";
				}
			}
		
			print OUTFILE "\r\n";
		}
        }

	close INFILE;
	close OUTFILE;

	print "\n";
	print "Success!  Input file $file has been converted to $output.\n"; 
}

main;


