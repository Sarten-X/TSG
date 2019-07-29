package TSG;
use base 'CGI::Application';

use strict; 
use warnings;

use Data::Dumper;
use POSIX;
################################################################################
# Configure
################################################################################
my $dataFile = "Data.csv";
my $sectionFile = "Sections.csv";

# A global object to handle our CSV files
my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1, sep_char  => ',', eol=>"\r\n" });
$csv->column_names(['ID', 'Section', 'Applicability', 'Symptom', 'Confirmation', 'Resolution', 'Author', 'Timestamp', 'References']);


################################################################################
# Initialize CGI::Application functionality
################################################################################
########################################
# Configure CGI::Application run modes
########################################
sub cgiapp_init {
	my $self = shift;
}

########################################
# Configure CGI::Application run modes
########################################
sub setup {
	my $self = shift;
	$self->start_mode('display'); # Default mode is to display the TSG 
	$self->mode_param('mode');
	$self->run_modes(
		'display' => 'display',
		'addItem' => 'addItem',
		'editItem' => 'editItem',
		'addSection' => 'addSection'
	);
}

################################################################################
# Application mode handlers
################################################################################
########################################
# Display the TSG via a HTML::Template.
########################################
sub display {
	my $self = shift;
		
	my $template = HTML::Template->new(filename => 'TSG.html', die_on_bad_params => 0, global_vars => 1 );

	# Read CSV file into a data structure
	my $sections = $self->loadData();
	
	# Isolate the sections as a sorted list
	my $sectionList = [];
	my $sectionCount = 0;
	foreach my $section (sort keys(%{$sections})) {
		# Give the section awareness of its position
		$sections->{$section}->{SectionNumber} = $sectionCount++;
		push(@$sectionList, $sections->{$section});
	}
		
	$template->param(
		Sections => $sectionList
	);
		

	return $template->output();
}

########################################
# Add a new item.
########################################
# Adding a new item is just generating a new ID (naively based on the current
# time), then editing it with new data.
sub addItem {
	my $self = shift;
	$self->query->Vars->{'idField'} = time;
	return $self->editItem();
}


########################################
# Edit an item.
########################################
# To edit an item, we copy all of the items that are not being changed, then
# modify one item with the new values from the HTML form. If no preexisting
# item matched the incoming item ID, we add a new item to the end of our list.
# We then write the item list to the data CSV file.
sub editItem {
	my $self = shift;
	
	my $modItem = {};
	$modItem->{'ID'} = $self->query->param('idField');
	$modItem->{'Section'} = $self->query->param('section');
	$modItem->{'Applicability'} = $self->query->param('applicability');
	$modItem->{'Symptom'} = $self->query->param('symptom');
	$modItem->{'Confirmation'} = $self->query->param('confirmation');
	$modItem->{'Resolution'} = $self->query->param('resolution');
	$modItem->{'Author'} = $ENV{'REMOTE_USER'};
	$modItem->{'Timestamp'} = time;
	$modItem->{'References'} = $self->query->param('references');
	
	my $itemSaved = 0;
	my $sections = $self->loadData();
	my $newItemsArrayRef = [];
	for my $section (values %{$sections}) {
		my $itemsArrayRef = $section->{'Items'};
		for my $item (@$itemsArrayRef) {
			my $newItem = {};
			if ($item->{'ID'} eq $self->query->param('idField')) {
				# Item is changing
				$newItem = $modItem;
				$itemSaved = 1;
			} else {
				# Deep clone the unchanging entries, arranging them for Text::CSV_XS
				$newItem->{'ID'} = $item->{'ID'};
				$newItem->{'Section'} = $item->{'Section'};
				$newItem->{'Applicability'} = $item->{'Applicability'};
				$newItem->{'Symptom'} = $item->{'Symptom'};
				$newItem->{'Confirmation'} = $item->{'Confirmation'};
				$newItem->{'Resolution'} = $item->{'Resolution'};
				$newItem->{'Author'} = $item->{'Author'};
				$newItem->{'Timestamp'} = $item->{'RawTimestamp'};
				$newItem->{'References'} = join("|", map(
					{ 
						$_->{'Reference'} =~ s/\|/\\|/g;
						$_ = $_->{'Reference'}
					}
					@{$item->{'References'}}
				));
			}
			push (@$newItemsArrayRef, $newItem);
		}
	}
	
	if (!$itemSaved) {
		push (@$newItemsArrayRef, $modItem);
	}
	
	open my $fh, ">", $dataFile or return $self->error("Output CSV error: $!");
	my $retval = $csv->csv(in => $newItemsArrayRef, out => $fh, eol => "\r\n");
	close $fh or return $self->error("Output CSV error: $!");
	
	return "ALL:" . Dumper($newItemsArrayRef) . "<br /><br /><br />" . Dumper($self->query);
}

################################################################################
# Common routines
################################################################################
########################################
# Load the data CSV into a data structure
########################################
sub loadData {

	my $self = shift;
	
	open my $fh, "<", $dataFile or return $self->error("Data CSV error: $!");
	my $data = $csv->csv(in => $fh, headers => "auto");
	close $fh or return $self->error("Data CSV error: $!");

	# Process CSV data into a deep data structure
	my $sections = {};
	foreach my $row (@$data) {
		# Find the appropriate section hash table
		my $sectionName = $row->{"Section"};
		my $section = $sections->{$sectionName} or {};
		
		$section->{"Name"} = $sectionName;
		
		# Retrieve the Items array from the section table
		my $itemsArrayRef = $section->{"Items"} || [];
		
		# Give each item awareness of its position
		$row->{"ItemNumber"} = scalar @{ $itemsArrayRef };
		
		# Separate the pipe-delimited reference list
		my @references = split(/(?<!\\)\|/, $row->{"References"});
		# Reset the references list in the data structure
		$row->{"References"} = [];
		# Unescape each reference, and insert it in the data structure
		foreach my $reference (@references) {
			$reference =~ s/\\\|/|/g;
			$reference =~ s/\\(.)/$1/g;;
			push(@{$row->{"References"}}, {Reference => $reference});
		}
		
		# 
		push(@$itemsArrayRef,$row);
		
		$row->{"RawTimestamp"} = $row->{"Timestamp"};
		$row->{"Timestamp"} = POSIX::strftime("%m/%d/%Y %H:%M:%S\n", localtime($row->{"Timestamp"}));
		
		$section->{"Items"} = $itemsArrayRef;
		$sections->{$sectionName} = $section;
	}
	return $sections;
}

########################################
# Write a friendy error page for soft errors (not HTTP 500)
########################################
sub error {
	my $self = shift;
	my $error = shift;
	return "<h1>Application Error: $error";
}
1;
