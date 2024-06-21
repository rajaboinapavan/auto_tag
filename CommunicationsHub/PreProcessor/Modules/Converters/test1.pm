package Test;

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
