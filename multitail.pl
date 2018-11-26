#!/usr/bin/perl -w

use strict;
use warnings;
use vars qw( @FILES %kinder $kind $file $wait );
$| = 1;

my $TOPT= ""; map { (/^-/) ? $TOPT .="$_ " : push @FILES, $_ } @ARGV;

FORK: while ($file = shift @FILES) {
	$kind = fork();
	last FORK unless $kind;
	$kinder{$kind} = 1;
};

## WHO AM I?
($kind) ? parent_process() : child_process() ;
exit(0);

## PARENT CODE
sub parent_process {
	use POSIX ":sys_wait_h";
	# wait until children have finished
	PARENT: do {
		# check children
		CHILD: foreach (keys %kinder) {
			$wait = waitpid($_,&WNOHANG);
			last CHILD unless ($wait == -1);
			delete $kinder{$_};
		};
		# sleep a while to reduce cpu usage
		select(undef, undef, undef, 0.5);
	} until ($wait == -1 or scalar keys %kinder <= 0);
};

## CHILD CODE
sub child_process {
	open (IN, "tail ".$TOPT.$file." |") or die "Can not tail -f $file: $!\n";
	while (<IN>) { print "$_" };
	close(IN);
};


