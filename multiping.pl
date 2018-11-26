#!/usr/bin/perl -W

## MODULES
use strict;
use warnings;
use IO::Pipe;
use Getopt::Long 2.25 qw(:config no_ignore_case bundling);
use vars qw( %OPTIONS %KINDER %STATS $PIPE );
$| = 1;


###############
## DEFINITIONS
###############

my $PINGCOUNT	= 3;
my $PINGDELAY	= 1;
my $FORKDELAY	= 0.5;


########
## MAIN
########

## PARSE COMMAND LINE AND INIT
GetOptions( \%OPTIONS,
  'verbose|v+',
  'loop|l',
  'count|c=i'	=> \$PINGCOUNT,
  'delay|d=i'	=> \$PINGDELAY,
) or die "\nWRONG ARGUMENTS!\n\n";
$OPTIONS{'verbose'} ||= 0;

## CHECK HOSTS
MAIN: while (1) {
	dbg("\nSTARTING\n\n");
	check_hostlist (@ARGV);
	dbg("\nFINISHED\n\n");
	last MAIN unless $OPTIONS{'loop'};
};
## FINISH PROGRAM
exit 0;


########
## SUBS
########

## MINI
sub out  { my $line = shift; print "$line", @_ };
sub dbg  { my $line = shift; print "$line", @_ if $OPTIONS{'verbose'} };
sub dev  { my $line = shift; print "$line", @_ if $OPTIONS{'verbose'}  > 1 };

## CHECK HOSTS: MAIN
sub check_hostlist {
	my @hostlist = @_; my $result = 0; undef my @status;
	$PIPE = new IO::Pipe;
	dbg("  CHECK: ".(join ', ', @hostlist)."\n");
	%KINDER = (); my $kind = undef; my $probe = '';
	FORK: while ($probe = shift @hostlist) {
		dbg("  PROBE: $probe\n");
		$kind = fork();
		last FORK unless $kind;
		$KINDER{$kind} = 1;
	};
	## WHO AM I?
	($kind) ? $result = parent_process(@hostlist) : child_process($probe);
	return $result;
};

## CHECK HOSTS: PARENT
sub parent_process {
  $PIPE->reader();
	my @hostlist = @_; my $result = 0; undef my @status; my $wait = undef;
	use POSIX ":sys_wait_h";
	# wait until children have finished
	dev("  parent process waiting for ".(scalar keys %KINDER)." pids ".(join ' ', (keys %KINDER))."\n");
	PARENT: do {
		# check pipe for finished children
		push @status, <$PIPE>;
		# check children
		CHILD: foreach (keys %KINDER) {
			$wait = waitpid($_,&WNOHANG);
			last CHILD unless ($wait == -1);
			delete $KINDER{$_};
		};
		# sleep a while to reduce cpu usage
		select(undef, undef, undef, $FORKDELAY);
		dev("  parent process waiting for ".(scalar keys %KINDER)." pids ".(join ' ', (keys %KINDER))."\n");
	} until (($wait == -1) or (($#status + 1) >= (scalar @hostlist)));
	dev("  parent process loop finished.\n");
	# display results
	foreach my $proc (@status) {
		chomp($proc);
		dev("  <P> $proc\n");
		if ($proc =~ /^([^:]+):([^:]+):([^:]+):([^:]+)$/) {
			my($pid, $dst, $snd, $res) = ($1, $2, $3, $4);
			$STATS{$dst} = $res.'/'.$snd;
			$result += $res;
		};
	};
  $PIPE->close();
  return $result;
};

## CHECK HOSTS: CHILD
sub child_process {
  $PIPE->writer();
  my $addr = shift; my $success = 0; my $transmit = 0; my $rtt = '';
  my @result = `ping -q -n -c$PINGCOUNT -i$PINGDELAY $addr 2>&1`;
  # send summary to parent
  map { ($transmit,$success) = ($1,$2) if /^(\d+) packets transmitted, (\d+) received/; $rtt = $_ if /^rtt/ } @result;
  printf "%3d/%-3d %15s: %s", $success, $transmit, $addr, (($success and $rtt) ? $rtt : "\n");
  my $proc = "$$:$addr:$transmit:$success";
  dev("  <C> $proc\n");
  print $PIPE "$proc\n";
  exit (0);
};


__END__

