#!C:/Perl5.10.1/bin/perl.exe

use 5.010;

use strict;
use warnings;

use FindBin qw($Bin);
use Fcntl qw(:flock);
use POSIX qw(strftime);

use lib $ENV{CCS_RESOURCE};
use lib_CCS others => ["$ENV{CCS_RESOURCE}/Global/Std"];
use AardvarkServices;

## -------------------------------------- BEGIN main() ------------------------------------------##

my ( $InspireJob, $InspireEnv, $ClientJob, $ClientRun ) = @ARGV;

open my $saveout, ">&STDOUT";
open STDOUT, '>', "/dev/null";

my $lock = get_lock();

my $aa_web_svc  = AardvarkServices->new();
my $inspire_run = $aa_web_svc->increment_contract_run_number($InspireJob)
	or die "AardvarkServices: Failed to get run number: " . $aa_web_svc->get_error();

unlock_it($lock);

open STDOUT, ">&", $saveout;

print $inspire_run;

exit 0;

## --------------------------------------- END main() -------------------------------------------##

sub get_lock {
	my $chub_ini      = CcsCommon::ini2h("$Bin/PreProcessor.ini");
	my $chub_contract = $chub_ini->{'general'}{'commhub_contract'};

	my $lockf = (
		CcsCommon::get_setting( 'GENERAL', 'gold_env' ) eq 'production'
		? $chub_ini->{'archive_base'}{'production'}
		: $chub_ini->{'archive_base'}{'non_prod'}
	) . "/$chub_contract/$InspireJob/RunNum.lock";

	open my $fh, '>>', $lockf or die "Failed to open '$lockf': $!\n";
	flock( $fh, LOCK_EX ) or die "Failed to lock '$lockf': $!\n";

	return $fh;
}

sub unlock_it {
	my $fh = shift;

	printf $fh (
		"[%s] %s %d => %s %d%s\n",
		strftime( '%Y%m%d %H%M%S', localtime ),
		$ClientJob,
		$ClientRun,
		$InspireJob,
		$inspire_run,
		{
			development => ' [DEV]',
			uat         => ' [QA]',
			preprod     => ' [PRE]',
			production  => '',
		}->{$InspireEnv},
	);

	close $fh;
	return;
}
