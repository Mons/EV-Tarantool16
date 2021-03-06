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
use Test::More;
BEGIN{ $ENV{TEST_FAST} and plan 'skip_all'; }
use Test::Deep;
use Data::Dumper;
use Renewer;
use Carp;
use Test::Tarantool16;

my %test_exec = (
	ping => 1,
	eval => 1,
	call => 1,
	select => 1,
	insert => 1,
	delete => 1,
	update => 1,
	upsert => 1,
);

my $cfs = 0;
my $connected;
my $disconnected;

my $w = AnyEvent->signal (signal => "INT", cb => sub { exit 0 });

my $tnt = {
	name => 'tarantool_tester',
	port => 11723,
	host => '127.0.0.1',
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
};

$tnt = Test::Tarantool16->new(
	title    => $tnt->{name},
	host     => $tnt->{host},
	port     => $tnt->{port},
	logger   => sub { diag ( $tnt->{title},' ', @_ ) if $ENV{TEST_VERBOSE}; },
	initlua  => $tnt->{initlua},
	wal_mode => 'write',
	on_die   => sub { fail "tarantool $tnt->{name} is dead!: $!"; exit 1; }
);

$tnt->start(timeout => 10, sub {
	my ($status, $desc) = @_;
	if ($status == 1) {
		EV::unloop;
	}
});
EV::loop;

$tnt->{cnntrace} = 0;
my $SPACE_NAME = 'tester';


my $c; $c = EV::Tarantool16->new({
	host => $tnt->{host},
	port => $tnt->{port},
	username => $tnt->{username},
	password => $tnt->{password},
	reconnect => 0.2,
	cnntrace => $tnt->{cnntrace},
	log_level => $ENV{TEST_VERBOSE} ? 4 : 0,
	connected => sub {
		diag Dumper \@_ unless $_[0];
		diag "connected: @_" if $ENV{TEST_VERBOSE};
		$connected++ if defined $_[0];
		EV::unloop;
	},
	connfail => sub {
		my $err = 0+$!;
		is $err, Errno::ECONNREFUSED, 'connfail - refused' or diag "$!, $_[1]";
		# $nc->(@_) if $cfs == 0;
		$cfs++;
		# and
		EV::unloop;
	},
	disconnected => sub {
		diag "discon: @_ / $!" if $ENV{TEST_VERBOSE};
		$disconnected++;
		EV::unloop;
	},
});

EV::now_update;
$c->connect;
EV::loop;

ok $connected > 0, "Connection is ok";
croak "Not connected normally" unless $connected > 0;


subtest 'Ping tests', sub {
	plan( skip_all => 'skip') if !$test_exec{ping};
	diag '==== Ping timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($opt, $cmp) = @_;
		$c->ping($opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[{timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{}, [
			{
				code => 0,
				sync => ignore(),
				schema_id => ignore(),
			}
		]],
		[{timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{timeout => 0.1}, [
			{
				code => 0,
				sync => ignore(),
				schema_id => ignore(),
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};

subtest 'Eval tests', sub {
	plan( skip_all => 'skip') if !$test_exec{eval};
	diag '==== Eval timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($opt, $cmp) = @_;
		$c->eval("return {box.info.status}", [], $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[{timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[{timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};

subtest 'Call tests', sub {
	plan( skip_all => 'skip') if !$test_exec{call};
	diag '==== Call timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($timeout, $opt, $cmp) = @_;
		$c->call("timeout_test", [$timeout], $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[1.0, {timeout => 0.5}, [
			undef,
			"Request timed out"
		]],
		[0.5, {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[0.5, {timeout => 0.2}, [
			undef,
			"Request timed out"
		]],
		[1.0, {timeout => 2.0}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};


subtest 'Select tests', sub {
	plan( skip_all => 'skip') if !$test_exec{ping};
	diag '==== Select timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($key, $opt, $cmp) = @_;
		$c->select($SPACE_NAME, $key, $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[[], {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{}, {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[[], {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{}, {timeout => 0.1}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};


subtest 'Insert tests', sub {
	plan( skip_all => 'skip') if !$test_exec{insert};
	diag '==== Insert timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($args, $opt, $cmp) = @_;
		$c->insert($SPACE_NAME, $args, $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[{_t1 => "t1", _t2 => "t2", _t3 => 180, _t4 => '-100', _t5 => 's' }, {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => "t1", _t2 => "t2", _t3 => 181, _t4 => '-100', _t5 => 's' }, {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[{_t1 => "t1", _t2 => "t2", _t3 => 182, _t4 => '-100', _t5 => 's' }, {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => "t1", _t2 => "t2", _t3 => 183, _t4 => '-100', _t5 => 's' }, {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};

subtest 'Delete tests', sub {
	plan( skip_all => 'skip') if !$test_exec{delete};
	diag '==== Delete timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($args, $opt, $cmp) = @_;
		$c->delete($SPACE_NAME, $args, $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[{_t1 => "t1", _t2 => "t2", _t3 => 180 }, {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => "t1", _t2 => "t2", _t3 => 181 }, {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[{_t1 => "t1", _t2 => "t2", _t3 => 182 }, {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => "t1", _t2 => "t2", _t3 => 183 }, {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};

subtest 'Update tests', sub {
	plan( skip_all => 'skip') if !$test_exec{update};
	diag '==== Update timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($key, $tuples, $opt, $cmp) = @_;
		$c->update($SPACE_NAME, $key, $tuples, $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[{_t1 => 't1',_t2 => 't2',_t3 => 17}, [ [3 => '+', 50] ], {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => 't1',_t2 => 't2',_t3 => 17}, [ [3 => '+', 50] ], {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[{_t1 => 't1',_t2 => 't2',_t3 => 17}, [ [3 => '+', 50] ], {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => 't1',_t2 => 't2',_t3 => 17}, [ [3 => '+', 50] ], {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore(),
			}
		]],
	];

	for my $p (@$plan) {
		$f->(@$p);
	}

};


subtest 'Upsert tests', sub {
	plan( skip_all => 'skip') if !$test_exec{update};
	diag '==== Upsert timeout tests ===' if $ENV{TEST_VERBOSE};

	my $f = sub {
		my ($tuple, $operations, $opt, $cmp) = @_;
		$c->upsert($SPACE_NAME, $tuple, $operations, $opt, sub {
			cmp_deeply \@_, $cmp;
			EV::unloop;
		});
		EV::loop;
	};


	my $plan = [
		[{_t1 => 't1',_t2 => 't2',_t3 => 17}, [ [3 => '+', 50] ], {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => 't1',_t2 => 't2',_t3 => 17, _t4 => 20, _t5 => 's'}, [ [3 => '=', 50] ], {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore()
			}
		]],
		[{_t1 => 't1',_t2 => 't2',_t3 => 17, _t4 => 20, _t5 => 's'}, [ [3 => '=', 50] ], {timeout => 0.00001}, [
			undef,
			"Request timed out"
		]],
		[{_t1 => 't1',_t2 => 't2',_t3 => 17, _t4 => 20, _t5 => 's'}, [ [3 => '=', 50] ], {}, [
			{
				sync => ignore(),
				schema_id => ignore(),
				code => 0,
				status => "ok",
				count => ignore(),
				tuples => ignore(),
			}
		]],
	];

	Renewer::renew_tnt($c, $SPACE_NAME, 0, sub {
		EV::unloop;
	});
	EV::loop;
	
	for my $p (@$plan) {
		$f->(@$p);
	}

};


done_testing();
