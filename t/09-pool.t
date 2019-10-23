package main;

use 5.010;
use strict;
use FindBin;
use lib "t/lib","lib","$FindBin::Bin/../blib/lib","$FindBin::Bin/../blib/arch";
use EV;
use Time::HiRes 'sleep','time';
use Scalar::Util 'weaken';
use Errno;
use EV::Tarantool16;
use EV::Tarantool16::Pool;
use Test::More;
BEGIN{ $ENV{TEST_FAST} and plan 'skip_all'; }
use Test::Deep;
use Data::Dumper;
use Carp;
use Test::Tarantool16;
# use Devel::Leak;
use AE;

$EV::DIED = sub {
	diag "@_" if $ENV{TEST_VERBOSE};
	EV::unloop;
	exit;
};

my $cfs = 0;
my $connected;
my $disconnected;

my $w = AnyEvent->signal (signal => "INT", cb => sub { exit 0 });

my $host = "127.0.0.1";
my @ports = (
	11103,
	11102,
);
my $peers = [];
push @{$peers}, "$host:$_", for @ports;

my @tnts = map { {
	name => 'tarantool_tester['.$_.']',
	port => $_,
	host => $host,
	username => 'test_user',
	password => 'test_pass',
	initlua => do {
		my $file = 't/tnt/app.lua';
		local $/ = undef;
		open my $f, "<", $file
			or die "could not open $file: $!";
		my $d = <$f>;
		close $f;
		$d;
	}
} } @ports;

@tnts = map { my $tnt = $_; Test::Tarantool16->new(
	title    => $tnt->{name},
	host     => $tnt->{host},
	port     => $tnt->{port},
	logger   => sub { diag ( $tnt->{name},' ', @_ ) if $ENV{TEST_VERBOSE};},
	initlua  => $tnt->{initlua},
	wal_mode => 'write',
	on_die   => sub { fail "tarantool $tnt->{name} is dead!: $!"; exit 1; },
) } @tnts;

for (@tnts) {
	$_->start(timeout => 10, sub {
		my ($status, $desc) = @_;
		if ($status == 1) {
			EV::unloop;
		} else {
			diag Dumper \@_ if $ENV{TEST_VERBOSE};
		}
	});
	EV::loop;

	my $w; $w = EV::timer 1, 0, sub {
		undef $w;
		EV::unloop;
	};
	EV::loop;
}

my $timeout = 5;
my $w_timeout; $w_timeout = AE::timer $timeout, 0, sub {
	undef $w_timeout;
	fail "Couldn't connect to Pool in $timeout seconds";
	EV::unloop;
};

my $name = "TestPool";
my $c; $c = EV::Tarantool16::Pool->new(
	name => $name,
	log_level => 0,
	cnntrace => 0,
	peers => $peers,
	on_available => sub {
		undef $w_timeout;
		diag Dumper \@_ unless $_[0];
		diag "connected: @_" if $ENV{TEST_VERBOSE};
		pass 'Pool connected';
		EV::unloop;
	},
	on_unavailable => sub {
		diag "disconnected: @_" if $ENV{TEST_VERBOSE};
	},
);

$c->connect;
EV::loop;

for (1..100) {
	$c->ping(sub {
		isnt shift, undef, 'ping request successful';
		EV::unloop;
	});
	EV::loop;
}
done_testing;

