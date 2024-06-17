#!C:/Strawberry/perl/bin/perl

# Version: 0.0.30
# Timestamp: 2024-06-18 00:03:04 +0530
# Author: d disk

# made change on 29 for 30

use v5.32;

use strict;
use warnings;

## ------------------------------- BEGIN Program Description ------------------------------------##
#
# This script converts input datafile(s) using the specified harness and converter.
# Currently, converted output files are assumed to be in .JSON format.
# The process invokes a helper script 'get_job_details.pl' to obtain:
#    1) the job bag details aka stream_setup.xml file
#    2) the quadient content object aka qco.json file
# Finally, it builds a startup file and invokes InspireRunJob for doc composition.
#
# This application runs as follows:
# C:\Strawberry\perl\bin\perl.exe \
#   connect2_convert.pl           \
#     --converter  <Converter>    \
#     --contract   <ClientJobNum> \
#     --run        <ClientRunNum> \
#     --inspirejob <InspireJob>   \
#     --inspireenv <InspireEnv>   \
#       <input_data_file>
#
# Alternatively, an Aardvark style --startupfile <StartupFile> option can be specified.
# <StartupFile> contains the following key=value parameters:
# DataFileName=<input_data_file>
# JobNumber=<ClientJobNum>
# RunNumber=<ClientRunNum>
# Extras=--inspirejob <InspireJob> --inspireenv <InspireEnv> --converter <Converter>
#
# <StartupFile> is parsed to extract all required options
# Most required command line options come from <StartupFile>
# Remaining required command line options are parsed from 'Extras' key in <StartupFile>
#
## --------------------------------- END Program Description ------------------------------------##

use Data::Printer;
use Getopt::Long;
use FindBin qw($Bin);
use IPC::Run qw(run);
use File::Copy;
use File::Basename;
use Date::Format;
use JSON;

## --------------------------------- BEGIN Global variables -------------------------------------##

my $INI_file = "$Bin/communications_hub.ini";

my %Options = (
	'startupfile=s' => \my $StartupFile,
	'contract=s'    => \my $ClientJobNum,#
	'run=i'         => \my $ClientRunNum,#
	'converter=s'   => \my $Converter,#
	'inspirejob=s'  => \my $InspireJob,#
	'inspireenv=s'  => \my $InspireEnv,#
	'inspirerun=i'  => \my $InspireRun,##############?????????????????
	'startuponly'   => \my $StartupOnly,
	'help'          => sub { usage(); exit 0 },
);

my %PP_startup;

## ---------------------------------- END Global variables --------------------------------------##
## -------------------------------------- BEGIN main() ------------------------------------------##

GetOptions(%Options);
my $DataFileName = $ARGV[0];

if ( defined $StartupFile ) {
	%PP_startup = parse_startupfile($StartupFile);

	$DataFileName = $PP_startup{'DataFileName'};
	$ClientJobNum = $PP_startup{'JobNumber'};
	$ClientRunNum = $PP_startup{'RunNumber'};

	#hack $PP_startup{'JobDescription'} =~ / DEV / and $InspireEnv = 'dev';

	if ( defined $PP_startup{'Extras'} ) {
		Getopt::Long::GetOptionsFromString( $PP_startup{'Extras'}, %Options );
	}
}

die "No input file specified! Use --help for usage\n"
	if not defined $DataFileName;

die "Specify a contract number with --contract. Use --help for usage\n"
	if not defined $ClientJobNum;

die "Specify a run number with --run. Use --help for usage\n"
	if not defined $ClientRunNum;

die "Specify a contract number with --inspirejob. Use --help for usage\n"
	if not defined $InspireJob;

die "Specify a converter with --converter. Use --help for usage\n"
	if not defined $Converter;

my $CHUB_ini = handle_ini_file($INI_file);
say "Communications Hub ini: ", np $CHUB_ini;

die "Invalid Communications Hub contract code '$InspireJob'\n"
	if $InspireJob !~ /^$CHUB_ini->{'general'}{'CommHubContract'}\d+$/;

$InspireEnv //=
	$ENV{'AREA'} eq 'DEVELOPMENT'
	? 'dev'
	: $CHUB_ini->{'helper'}{'get_ccs_setting'}->('gold_env');

die "No such inspire_env '$InspireEnv' specified in '$INI_file'\n"
	if not exists $CHUB_ini->{'inspire_env'}{$InspireEnv};

die "Missing Converter '$Converter' specification in '$INI_file'\n"
	if not exists $CHUB_ini->{'converter'}{$Converter};

# build InspireRunJob startup file from Preprocessor startup
my $inspire_startup_file = build_startupfile(%PP_startup);

# call InspireRunJob.exe with the Inspire Startup File
my @inspire_runjob_cmd = ( $CHUB_ini->{'general'}{'InspireRunJob'} );
push @inspire_runjob_cmd, '--startupfile', $inspire_startup_file;
say 'RUNNING: ' . join( ' ', @inspire_runjob_cmd );

# exit if --startuponly is set; this is to test startup file creation only
die "Option --startuponly set. Exiting\n" if defined $StartupOnly;

run \@inspire_runjob_cmd;

exit 0;

## --------------------------------------- END main() -------------------------------------------##

sub parse_startupfile {
	my $startupfile = shift;

	if ( not -f $startupfile ) {
		die "startup file '$startupfile' not found!\n";
	}

	my %parsed;

	open my $STARTUPFH, '<', $startupfile                             
		or die "Failed to read startup file '$startupfile': $!\n";

	while (<$STARTUPFH>) {
		s/\r?\n$//ms;
		s/\s+$//;
		my ( $key, $value ) = split /=/, $_, 2;

		# more Perl-y
		$value = undef if '(null)' eq $value;

		# handle generically
		if ( exists $parsed{$key} ) {
			if ( ref $parsed{$key} ) {
				push @{ $parsed{$key} }, $value;
			}
			else {
				$parsed{$key} = [ $parsed{$key}, $value ];
			}
		}
		else {
			$parsed{$key} = $value;
		}
	}

	close $STARTUPFH;

	if ( defined $parsed{'ErrorFile'} ) {
		say "REDIRECTING STDERR to '$parsed{ErrorFile}'";
		open STDERR, '>>', $parsed{'ErrorFile'}
			or die "ERROR redirecting STDERR: $!";
		STDERR->autoflush(1);
	}
	else {
		die "ERROR redirecting STDERR: $!";
	}

	if ( defined $parsed{'TraceFile'} ) {
		say "REDIRECTING STDOUT to '$parsed{TraceFile}'";
		open STDOUT, '>>', $parsed{'TraceFile'}
			or die "ERROR redirecting STDOUT: $!";
		STDOUT->autoflush(1);
	}
	else {
		die "ERROR redirecting STDOUT: $!";
	}

	return %parsed;
}

sub handle_ini_file {
	my $ini_file = shift;

	if ( not -f $ini_file ) {
		die "INI file '$ini_file' not found!\n";
	}

	open my $INIFH, '<', $ini_file
		or die "Failed to read INI file '$ini_file': $!\n";

	my $init;
	my $section = 'general';

	while (<$INIFH>) {
		s/\r?\n$//ms;
		s/\s+$//;

		next if /^#/ || /^$/;

		if (/^\[(\w+)\]$/) {
			$section = $1;
			next;
		}

		my ( $key, $value ) = split /=/, $_, 2;

		$value = undef if '(null)' eq $value;
		$value = [ split( ',', $value ) ] if $value =~ /,/;

		$init->{$section}{$key} = $value;
	}

	close $INIFH;

	my $irje = $init->{'general'}{'InspireRunJob'};
	$irje =~ s/\%(\w+)\%/$ENV{$1}/e;
	$irje =~ s/\\/\//g;
	die "No such executable '$irje'\n" if not -x $irje;
	$init->{'general'}{'InspireRunJob'} = $irje;

	foreach my $key ( keys %{ $init->{'stack'} } ) {
		my $exe = $init->{'stack'}{$key};
		$exe =~ s/\%(\w+)\%/$ENV{$1}/e;
		$exe =~ s/\\/\//g;
		die "No such executable '$exe'\n" if not -x $exe;
		$init->{'stack'}{$key} = $exe;
	}

	# validate the converter harnesses
	foreach my $key ( keys %{ $init->{'harness'} } ) {
		my ( $stack, $script ) = @{ $init->{'harness'}{$key} };
		die "Invalid stack '$stack' for harness '$key'\n"
			if not exists $init->{'stack'}{$stack};
		$stack  = $init->{'stack'}{$stack};
		$script = "$Bin/$script";
		die "No such script '$script'\n" if not -f $script;
		$init->{'harness'}{$key} = [ $stack, $script ];
	}

	# also, validate the 'helper' scripts
	foreach my $key ( keys %{ $init->{'helper'} } ) {
		my ( $stack, $script ) = @{ $init->{'helper'}{$key} };
		die "Invalid stack '$stack' for helper '$key'\n"
			if not exists $init->{'stack'}{$stack};
		$stack  = $init->{'stack'}{$stack};
		$script = "$Bin/$script";
		die "No such script '$script'\n" if not -f $script;
		$init->{'helper'}{$key} = sub {
			my @command = ( $stack, $script, @_ );
			say 'RUNNING: ' . join( ' ', @command );
			run \@command, '>', \my $output;
			return $output;
		};
	}

	foreach my $key ( keys %{ $init->{'converter'} } ) {
		my $harness = $init->{'converter'}{$key}[0];
		die "Invalid harness '$harness' for converter '$key'\n"
			if not exists $init->{'harness'}{$harness};
		die "Invalid / missing Q2G_type for converter '$key'\n"
			if not defined $init->{'converter'}{$key}[1];
	}

	return $init;
}

sub convert_input {
	my $converter = shift;

	my $filename = basename($DataFileName);
	move $DataFileName, '.'
		or die "Could not move '$filename' to current dir: $!\n";

	# build the command for run()
	my @command = @{ $CHUB_ini->{'harness'}{ $converter->[0] } };
	push @command, '--converter', $Converter;
	push @command, '--contract',  $ClientJobNum;
	push @command, '--run',       $ClientRunNum;
	push @command, '--file',      $filename;

	say 'RUNNING: ' . join( ' ', @command );
	run \@command, '>', \my $output;
	say $output;

	my $jsonfile;
	while ( $output =~ /^(.+) -> (.+)$/mg ) {
		if ( $1 eq $filename ) {
			$jsonfile = $2;
			last;
		}
	}

	die "'$Converter' converter failed to convert '$filename'\n"
		if !( defined $jsonfile && -f $jsonfile && $jsonfile =~ /\.json$/i );

	return ( $filename, $jsonfile );
}

sub build_startupfile {
	my %job_params = @_;

	say "Preprocessor params: ", np %job_params;

	# convert the input data to JSON using harness and converter module
	my ( $inputfile, $outputfile ) = convert_input( $CHUB_ini->{'converter'}{$Converter} );
	my ($doc_type) = ( $outputfile =~ /\.(\w+)\.json$/i );

	# build the additional encompass quadient content object JSON file
	my $qco_json_file = "${ClientJobNum}.${ClientRunNum}.QCO.json";
	my $qco_json_str  = $CHUB_ini->{'helper'}{'get_encompass_qco'}->($ClientJobNum);
	open my $qco_fh, '>', $qco_json_file or die "Failed to open '$qco_json_file': $!\n";
	print $qco_fh $qco_json_str;
	close $qco_fh;

	my $qco_data = decode_json($qco_json_str);
	my $approval = $qco_data->{'content'}{'data'}[0]{'operations_details'}{'requires_approval_yn'} || 'No';

	# now, let's construct this very long Extras argument for the Inspire job
	#Extras= \
	# --aardvarkAppAdminUri https://CSAVARDWEBt...    <-- from get_job_details()
	# --addJobQueue         true                      <-- CONSTANT
	# --environment         ccsccmusbld01             <-- command line option --inspireenv
	# --icmRegion           US                        <-- CONSTANT
	# --jobConfigName       JobConfig_${doc_type}.xml <-- $doc_type is from JSON filename
	# --q2g                 true                      <-- CONSTANT
	# --site                processing                <-- from get_job_details()
	# --streamSetupXML      stream_setup.xml          <-- from get_job_details()

	my $stream_setup_xml = "stream_setup_${ClientJobNum}_${ClientRunNum}.xml";
	open my $ssx_fh, '>', $stream_setup_xml or die "Failed to open '$stream_setup_xml': $!\n";
	print $ssx_fh $CHUB_ini->{'helper'}{'get_stream_setup'}->($ClientJobNum);
	close $ssx_fh;

	my $get_ccs_setting = $CHUB_ini->{'helper'}{'get_ccs_setting'};

	my %startup_extras = (
		streamSetupXML      => $stream_setup_xml,
		site                => $get_ccs_setting->('site'),
		aardvarkAppAdminUri => $get_ccs_setting->('aardvark_web_svc_appadmin_proxy'),
		environment         => $CHUB_ini->{'inspire_env'}{$InspireEnv},
		jobConfigName       => "JobConfig_${doc_type}.xml",
		addJobQueue         => 'true',
		q2g                 => 'true',
		icmRegion           => 'US',
	);

	$InspireRun //= $ENV{'AREA'} eq 'DEVELOPMENT'
		? $CHUB_ini->{'default'}{'DevInspireRunNumber'}    # using 'default' value for 'DEVELOPMENT' environment
		: $CHUB_ini->{'helper'}{'get_chub_run_num'}->( $InspireJob, $ClientJobNum, $ClientRunNum );

	my $today_and_now = time2str( '%j.%H%M%S', time );
	my $startup_filename = "${InspireJob}.${InspireRun}.${today_and_now}.startup.txt";

	( my $progress_filename = $startup_filename ) =~ s/startup/progress/;
	( my $trace_filename    = $startup_filename ) =~ s/startup/trace/;
	( my $error_filename    = $startup_filename ) =~ s/startup/error/;

	my $today = time2str( '%A, %B %d, %Y', time );    # e.g. Friday, February 02, 2024

	my $job_description = "$InspireJob Communication Hub - $ClientJobNum $doc_type - Run #$InspireRun";

	my %inspire_startup = (
		JobNumber        => $InspireJob,
		ClientCode       => $CHUB_ini->{general}{'CommHubContract'},
		RunNumber        => $InspireRun,
		JobDescription   => $job_description,
		ProcessingScript => $CHUB_ini->{'general'}{'InspireRunJob'},
		DataFileName     => [ $inputfile, $outputfile, $qco_json_file ],
		Extras           => join( ' ', map { "--$_ $startup_extras{$_}" } sort keys %startup_extras ),

		StartupFileName => $startup_filename,
		ProgressFile    => $progress_filename,
		TraceFile       => $trace_filename,
		ErrorFile       => $error_filename,

		# adding custom key to be used later in Q2G
		_requireSignOffYN => $approval,
		_Q2GType          => $CHUB_ini->{'converter'}{$Converter}[1],

		# copy these values from converter job_params file or assign 'default' for DEVELOPMENT

		EmailAddresses_FailedToQueue => $job_params{'EmailAddresses_FailedToQueue'}
			// $CHUB_ini->{'default'}{'support_email'},
		EmailAddresses_Failed => $job_params{'EmailAddresses_Failed'} // $CHUB_ini->{'default'}{support_email},

		ComputerName   => $job_params{'ComputerName'}   // $ENV{'COMPUTERNAME'},
		UserName       => $job_params{'UserName'}       // "$ENV{'USERDOMAIN'}\\$ENV{'USERNAME'}",
		ProcessingDate => $job_params{'ProcessingDate'} // $today,
		LastUpdate     => $job_params{'LastUpdate'}     // $today,

		SLAProcessCode  => $job_params{'SLAProcessCode'}  // 'All',
		Product         => $job_params{'Product'}         // '(null)',
		Package         => $job_params{'Package'}         // '(null)',
		PackageType     => $job_params{'PackageType'}     // '(null)',
		PackageVersion  => $job_params{'PackageVersion'}  // '(null)',
		ExternalDBJobId => $job_params{'ExternalDBJobId'} // '(null)',

		TestFlag         => $job_params{'TestFlag'}         // 0,
		JobId            => $job_params{'JobId'}            // 0,
		JobStatusId      => $job_params{'JobStatusId'}      // 0,
		JobQueueId       => $job_params{'JobQueueId'}       // 0,
		LinkedJobQueueId => $job_params{'LinkedJobQueueId'} // 0,
		ProcessId        => $job_params{'ProcessId'}        // 0,
		Priority         => $job_params{'Priority'}         // 1,
	);

	say "InspireRunJob startup: ", np %inspire_startup;

	open my $startup_fh, '>', $startup_filename or die "Failed to open $startup_filename: $!\n";

	# add sorted key=value pairs from job_params hash to job_params file
	foreach my $key ( sort keys %inspire_startup ) {
		my $value = $inspire_startup{$key};
		next if not defined $value;

		if ( ref($value) eq 'ARRAY' ) {
			map { print $startup_fh "$key=$_\n" } sort @{$value};
		}
		else {
			print $startup_fh "$key=$value\n";
		}
	}

	close $startup_fh;

	say "Created InspireRunJob startup file '$startup_filename'";
	return $startup_filename;
}

sub usage {
	my ($cmd) = $0 =~ /^.*?[\\\/]?([^\\\/]+?)(?:\.\w{1,4})?$/;

	print <<"EOF";
 $cmd: Calls the specified tech stack harness to convert a file

Options:
  --startupfile  <FILE>         Aardvark auto-proc INIFH file
  --inspirejob   <CONTRACT>     Communications Hub contract code
  --converter    <CONVERTER>    converter name (see .ini file)

Development Options:
  --inspireenv   <ENV>          inspire env e.g. dev (optional)
  --inspirerun   <RUN_NUMBER>   inspire run number(optional)
  --contract     <CONTRACT>     client job number
  --run          <NUMBER>       client run number

  --startuponly                 build inspire INIFH file only; 
                                do not execute InspireRunJob
  --help                        print this usage message
EOF

	return;
}
