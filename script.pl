#!C:/Strawberry/perl/bin/perl

# Version: ..1
# Timestamp: 2024-06-04 00:39:40 +0530
# Author: Pavan Kumar

change 43


use v5.32;

use strict;
use warnings;

## ------------------------------- BEGIN Program Description ------------------------------------##
#
# This script converts input datafile(s) using the specified communications hub job and converter.
# Converted output files are in .JSON format. Communications Hub contract starts with 800CH.
#
# The process invokes multiple helper scripts to obtain (see [helper] section in PreProcessor.ini)
#
# 1) get_ccs_setting.pl - get parameter value from [general] section from ccssite.ini
# 2) get_chub_run_num.pl - get run number from Aardvark for given communications hub job
# 3) get_client_run_num.pl - get run number from Aardvark for given client contract job
# 4) get_encompass_qco.pl - get JSON content from Encompass for given client contract job
# 5) get_stream_setup.pl - get stream setup from Aardvark for given client contract job
#
# Finally, it builds a startup file and invokes InspireRunJob.exe for doc composition.
#
# This application runs as follows:
# C:\Strawberry\perlin\perl.exe \
#   connect2_convert.pl           \
#     --converter  <Converter>    \
#     --contract   <ClientJob>    \
#     --inspirejob <InspireJob>   \
#     --inspireenv <InspireEnv>   \
#       <input_data_file>
#
# Alternatively, an Aardvark style --startupfile <StartupFile> can be used as follows:
# C:\Strawberry\perlin\perl.exe \
#   connect2_convert.pl --startupfile <StartupFile>
#
# where <StartupFile> contains the following key=value parameters:
# DataFileName=<input_data_file>
# JobNumber=<ClientJob>
# RunNumber=<ClientRun>
# Extras=--inspirejob <InspireJob> --converter <Converter> --inspireenv <InspireEnv>
#
# All required command line options come from 'Extras=' key in <StartupFile>
# The default for optional --inspireenv argument, is 'gold_env' parameter from ccssite.ini.
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

my $INI_file = "$Bin/PreProcessor.ini";

my %Options = (
	'startupfile=s' => \my $StartupFile,
	'contract=s'    => \my $ClientJob,
	'converter=s'   => \my $Converter,
	'inspirejob=s'  => \my $InspireJob,
	'inspireenv=s'  => \my $InspireEnv,
	'startuponly'   => \my $StartupOnly,
	'help'          => sub { usage(); exit 0 },
);

my %PP_startup;
my $CHUB_ini;

## ---------------------------------- END Global variables --------------------------------------##
## -------------------------------------- BEGIN main() ------------------------------------------##

GetOptions(%Options);
my $DataFileName = $ARGV[0];

if ( defined $StartupFile ) {
	%PP_startup = parse_startupfile($StartupFile);

	$DataFileName = $PP_startup{'DataFileName'};
	$ClientJob    = $PP_startup{'JobNumber'};

	#hack $PP_startup{'JobDescription'} =~ / DEV / and $InspireEnv = 'development';

	if ( defined $PP_startup{'Extras'} ) {
		Getopt::Long::GetOptionsFromString( $PP_startup{'Extras'}, %Options );
	}

	say "Preprocessor startup: ", np %PP_startup;
}

die "No input file specified! Use --help for usage
"
	if not defined $DataFileName;

die "Specify a contract number with --contract. Use --help for usage
"
	if not defined $ClientJob;

die "Specify a contract number with --inspirejob. Use --help for usage
"
	if not defined $InspireJob;

die "Specify a converter with --converter. Use --help for usage
"
	if not defined $Converter;

$CHUB_ini = handle_ini_file($INI_file);
say "Communications Hub ini: ", np $CHUB_ini;

die "Invalid Communications Hub contract code '$InspireJob'
"
	if $InspireJob !~ /^$CHUB_ini->{'general'}{'commhub_contract'}\d+$/;

$InspireEnv //= $CHUB_ini->{'helper'}{'get_ccs_setting'}->('gold_env');

die "No such inspire_env '$InspireEnv' specified in '$INI_file'
"
	if not exists $CHUB_ini->{'inspire_env'}{$InspireEnv};

die "Missing Converter '$Converter' specification in '$INI_file'
"
	if not exists $CHUB_ini->{'converter'}{$Converter};

# build InspireRunJob startup file from Preprocessor startup
my $inspire_startup_file = build_startupfile();

# call InspireRunJob.exe with the Inspire Startup File
my @inspire_runjob_cmd = ( $CHUB_ini->{'general'}{'inspire_runjob'} );
push @inspire_runjob_cmd, '--startupfile', $inspire_startup_file;
say 'RUNNING: ' . join( ' ', @inspire_runjob_cmd );

# exit if --startuponly is set; this is to test startup file creation only
die "Option --startuponly set. Exiting
" if defined $StartupOnly;

run \@inspire_runjob_cmd;

exit 0;

## --------------------------------------- END main() -------------------------------------------##

sub parse_startupfile {
	my $startupfile = shift;

	if ( not -f $startupfile ) {
		die "startup file '$startupfile' not found!
";
	}

	my %parsed;

	open my $STARTUPFH, '<', $startupfile
		or die "Failed to read startup file '$startupfile': $!
";

	while (<$STARTUPFH>) {
		s/
?
$//ms;
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
		die "INI file '$ini_file' not found!
";
	}

	open my $INIFH, '<', $ini_file
		or die "Failed to read INI file '$ini_file': $!
";

	my $init;
	my $section = 'general';

	while (<$INIFH>) {
		s/
?
$//ms;
		s/\s+$//;

		next if /^[;#]/ || /^$/;

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

	my $irje = $init->{'general'}{'inspire_runjob'};
	$irje =~ s/\%(\w+)\%/$ENV{$1}/e;
	$irje =~ s/\/\//g;
	die "No such executable '$irje'
" if not -x $irje;
	$init->{'general'}{'inspire_runjob'} = $irje;

	foreach my $key ( keys %{ $init->{'stack'} } ) {
		my $exe = $init->{'stack'}{$key};
		$exe =~ s/\%(\w+)\%/$ENV{$1}/e;
		$exe =~ s/\/\//g;
		die "No such executable '$exe'
" if not -x $exe;
		$init->{'stack'}{$key} = $exe;
	}

	# validate the converter harnesses
	foreach my $key ( keys %{ $init->{'harness'} } ) {
		my ( $stack, $script ) = @{ $init->{'harness'}{$key} };
		die "Invalid stack '$stack' for harness '$key'
"
			if not exists $init->{'stack'}{$stack};
		$stack  = $init->{'stack'}{$stack};
		$script = "$Bin/$script";
		die "No such script '$script'
" if not -f $script;
		$init->{'harness'}{$key} = [ $stack, $script ];
	}

	# also, validate the 'helper' scripts
	foreach my $key ( keys %{ $init->{'helper'} } ) {
		my ( $stack, $script ) = @{ $init->{'helper'}{$key} };
		die "Invalid stack '$stack' for helper '$key'
"
			if not exists $init->{'stack'}{$stack};
		$stack  = $init->{'stack'}{$stack};
		$script = "$Bin/$script";
		die "No such script '$script'
" if not -f $script;
		$init->{'helper'}{$key} = sub {
			my @command = ( $stack, $script, @_ );
			say 'RUNNING: ' . join( ' ', @command );
			run \@command, '>', \my $output;
			return $output;
		};
	}

	foreach my $key ( keys %{ $init->{'converter'} } ) {
		my $harness = $init->{'converter'}{$key}[0];
		die "Invalid harness '$harness' for converter '$key'
"
			if not exists $init->{'harness'}{$harness};
		die "Invalid / missing Q2G_type for converter '$key'
"
			if not defined $init->{'converter'}{$key}[1];
	}

	return $init;
}

sub convert_input {
	my ( $client_job, $client_run ) = @_;

	my $filename = basename($DataFileName);
	move $DataFileName, '.'
		or die "Could not move '$filename' to current dir: $!
";

	my $harness = $CHUB_ini->{'converter'}{$Converter}[0];

	# build the command for run()
	my @command = @{ $CHUB_ini->{'harness'}{$harness} };
	push @command, '--converter', $Converter;
	push @command, '--contract',  $client_job;
	push @command, '--run',       $client_run;
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

	die "'$Converter' converter failed to convert '$filename'
"
		if !( defined $jsonfile && -f $jsonfile && $jsonfile =~ /\.json$/i );

	return ( $filename, $jsonfile );
}

sub build_startupfile {
	# Client contract run number:
	# if development environment, then get run number uding Aardvark web service
	# if Aardvark startupfile is used, then get run number from the startupfile
	my $client_run =
		( $ENV{'AREA'} eq 'DEVELOPMENT' && $ENV{'DEVELOPMENT'} )
		? $CHUB_ini->{'helper'}{'get_client_run_num'}->($ClientJob)
		: $PP_startup{'RunNumber'};

	die "Missing or Invalid Client Run Number '$client_run'
"
		if not( defined $client_run && $client_run =~ /^\d+$/ );

	my $inspire_run =
		$CHUB_ini->{'helper'}{'get_chub_run_num'}->( $InspireJob, $InspireEnv, $ClientJob, $client_run );

	die "Missing or Invalid Inspire Run Number '$inspire_run'
"
		if !( defined $inspire_run && $inspire_run =~ /^\d+$/ );

	# convert the input data to JSON using harness and converter module
	my ( $inputfile, $outputfile ) = convert_input( $ClientJob, $client_run );

	# build the additional encompass quadient content object JSON file
	my $qco_json_file = "${ClientJob}.${client_run}.QCO.json";
	my $qco_json_str  = $CHUB_ini->{'helper'}{'get_encompass_qco'}->($ClientJob);
	open my $qco_fh, '>', $qco_json_file or die "Failed to open '$qco_json_file': $!
";
	print $qco_fh $qco_json_str;
	close $qco_fh;

	$outputfile =~ /\.(\w+)\.json$/i and my $doc_type = $1;

	my $job_description = "$InspireJob - Step 4 - Communications Hub ";
	$job_description .= ( $InspireEnv =~ /^dev/i ? 'DEV ' : 'QA ' ) if $InspireEnv !~ /^prod/i;
	$job_description .= "- $ClientJob Run #$client_run $doc_type - Run #$inspire_run";

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

	my $stream_setup_xml = "stream_setup_${ClientJob}_${client_run}.xml";
	open my $ssx_fh, '>', $stream_setup_xml or die "Failed to open '$stream_setup_xml': $!
";
	print $ssx_fh $CHUB_ini->{'helper'}{'get_stream_setup'}->($ClientJob);
	close $ssx_fh;

	( my $job_config_name = $outputfile ) =~ s/\.(\w+)\.json$/JobConfig_$1.xml/;

	my $get_ccs_setting = $CHUB_ini->{'helper'}{'get_ccs_setting'};

	my %startup_extras = (
		streamSetupXML      => $stream_setup_xml,
		site                => $get_ccs_setting->('site'),
		aardvarkAppAdminUri => $get_ccs_setting->('aardvark_web_svc_appadmin_proxy'),
		environment         => $CHUB_ini->{'inspire_env'}{ lc $InspireEnv },
		jobConfigName       => "JobConfig_${doc_type}.xml",
		addJobQueue         => 'true',
		q2g                 => 'true',
		icmRegion           => 'US',
	);

	my $today_and_now = time2str( '%j.%H%M%S', time );
	my $startup_filename = "${InspireJob}.${inspire_run}.${today_and_now}.startup.txt";

	( my $progress_filename = $startup_filename ) =~ s/startup/progress/;
	( my $trace_filename    = $startup_filename ) =~ s/startup/trace/;
	( my $error_filename    = $startup_filename ) =~ s/startup/error/;

	my %inspire_startup = (
		JobNumber        => $InspireJob,
		ClientCode       => $CHUB_ini->{'general'}{'commhub_contract'},
		RunNumber        => $inspire_run,
		DataFileName     => [ $inputfile, $outputfile, $qco_json_file ],
		JobDescription   => $job_description,
		Extras           => join( ' ', map { "--$_ $startup_extras{$_}" } sort keys %startup_extras ),
		StartupFileName  => $startup_filename,
		ProgressFile     => $progress_filename,
		TraceFile        => $trace_filename,
		ErrorFile        => $error_filename,
		ProcessingScript => $CHUB_ini->{'general'}{'inspire_runjob'},
		SLAProcessCode => $PP_startup{'SLAProcessCode'} // 'All',
		Product        => $PP_startup{'Product'}        // '(null)',
		# following custom keys are used during post-processing in Q2G step
		_requireSignOffYN =>
			decode_json($qco_json_str)->{'content'}{'data'}[0]{'operations_details'}{'requires_approval_yn'} || 'No',
		_Q2GType => $CHUB_ini->{'converter'}{$Converter}[1],
	);

	$inspire_startup{'ProcessingScript'} = '(null)' if defined $StartupOnly;

	say "InspireRunJob startup: ", np %inspire_startup;

	open my $startup_fh, '>', $startup_filename or die "Failed to open $startup_filename: $!
";

	foreach my $key ( sort keys %inspire_startup ) {
		my $value = $inspire_startup{$key};
		$value = '(null)' if not defined $value;

		if ( ref($value) eq 'ARRAY' ) {
			foreach ( sort @{$value} ) {
				$_ = '(null)' if not defined $_;
				print $startup_fh "$key=$_
";
			}
		}
		else {
			print $startup_fh "$key=$value
";
		}
	}

	close $startup_fh;

	say "Created InspireRunJob startup file '$startup_filename'";
	return $startup_filename;
}

sub usage {
	my ($cmd) = $0 =~ /^.*?[\/]?([^\/]+?)(?:\.\w{1,4})?$/;

	print <<"EOF";
 $cmd: Calls the specified tech stack harness to convert a file

Options:
  --startupfile  <FILE>         Aardvark auto-proc startup file

Development Options:
  --contract     <CONTRACT>     client job number
  --inspirejob   <CONTRACT>     Communications Hub contract code
  --converter    <CONVERTER>    converter name (see .ini file)
  --inspireenv   <GOLD_ENV>     inspire env e.g. uat (optional)

  --startuponly                 build inspire INIFH file only; 
                                do not execute InspireRunJob
  --help                        print this usage message
EOF

	return;
}
