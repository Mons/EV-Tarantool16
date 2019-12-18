package EV::Tarantool16::Pool;

use 5.010;
use strict;
use warnings;
no warnings 'uninitialized';
use AnyEvent;
use EV::Tarantool16;
use Scalar::Util qw(weaken);

=for rem
---
	instance:
		common: option
		peers:
			- host: xxx
			  port: yyy
			  username: xxx
			  password: yyy
			- "username:password@host:port"
...
=cut

sub log_error {
	my $self = shift;
	warn sprintf("[ERR] ".shift, @_). "\n" if $self->{log_level} >= 1;
}

sub log_warn {
	my $self = shift;
	warn sprintf("[WARN] ".shift, @_). "\n" if $self->{log_level} >= 2;
}

sub log_info {
	my $self = shift;
	warn sprintf("[INFO] ".shift, @_). "\n" if $self->{log_level} >= 3;
}

sub ready {
	my $self = shift;
	return 0+@{ $self->{rws} };
}

sub status {
	my $self = shift;
	return 'unavail' unless keys %{ $self->{states} };
	return join "; ",
		map { "$_:".join ",",map{ $_->{name}} values %{$self->{states}{$_}} } sort {
		($a eq 'active-rw') <=> ($b eq 'active-rw')
		||
		($a eq 'active-ro') <=> ($b eq 'active-ro')
		||
		(0+keys %{$self->{states}{$a}}) <=> (0+keys %{$self->{states}{$b}})
	} keys %{$self->{states}};
}

sub new {
	my $pkg = shift;
	my $self = bless {
		timeout => 1,
		reconnect => 1/3,
		ping_interval => 2/3,
		cnntrace => 1,
		ares_reuse => 0,
		wbuf_limit => 16000,
		servers => [],
		log_level => 3,
		connected => undef,
		disconnected => undef,
		peers => [],
		@_,
		stores => [],
	}, $pkg;
	
	my $peers = delete $self->{peers};
	$self->{peers} = [];
	
	my $id = 0;
	for my $peer (@$peers) {
		my %inst_cfg;
		my $name;
		if (ref $peer) {
			%inst_cfg = (read_buffer => 0x100000, %$peer);
		}
		elsif ($peer =~ m{^(?:|(?<username>[^:@]+):(?<password>[^:]+)\@)(?<host>[^:]+)(?::(?<port>\d+)|)$}) {
			%inst_cfg = (read_buffer => 0x100000, %+);
		}
		else {
			die "Bad peer config: $peer\n";
		}
		push @{$self->{peers}}, {
			cfg => \%inst_cfg,
			state => 'unavail',
			peer => "$inst_cfg{host}:$inst_cfg{port}",
			name => sprintf("%d/%s:%s", $id, $inst_cfg{host}, $inst_cfg{port}),
		};
		++$id;
	}
	my %by_state;
	$self->{states} = \%by_state;
	my $warned;
	for my $inst (@{$self->{peers}}) {
		$inst->{checker} = sub {
			my ($inst, $cnn, $cb) = @_;
			$cnn->call('dostring',['
				local max_lag = 0;
				for _,peer in pairs(box.info.replication) do
					if peer.upstream then
						max_lag = (not max_lag or max_lag < peer.upstream.lag) and peer.upstream.lag or max_lag
					end
				end
				return {
					id = box.info.id;
					ro = box.info.ro;
					rw = box.info.ro == false;
					cluster = box.info.cluster.uuid;
					lag = max_lag;
				}
			'], sub {
				if (my $res = shift) {
					if ($res->{count}) {
						$cb->($res->{tuples}[0][0]);
					}
					else {
						$cb->(undef, "Empty reply", $res);
					}
				}
				else {
					$cb->(undef, @_);
				}
			});
		};
		$inst->{set_state} = sub {
			my ($inst,$state) = @_;
			if ($inst->{state} ne $state) {
				my $old_active_rw = 0+keys %{ $by_state{'active-rw'} };
				delete $by_state{$inst->{state}}{ $inst->{name} };
				delete $by_state{$inst->{state}} unless %{ $by_state{$inst->{state}} };
				$self->log_info("Pool %s [%s]: %s -> %s", $self->{name}, $inst->{name}, $inst->{state}, $state);
				$inst->{state} = $state;
				$by_state{$inst->{state}}{ $inst->{name} } = $inst;
				my $new_active_rw = 0+keys %{ $by_state{'active-rw'} };
				
				@{ $self->{rws} } = values %{ $by_state{'active-rw'} };
				
				if ($old_active_rw == 0 and $new_active_rw > 0) {
					$self->{on_available} and $self->{on_available}($self);
				}
				elsif ($old_active_rw > 0 and $new_active_rw == 0) {
					$self->{on_unavailable} and $self->{on_unavailable}($self);
				}
			}
		};
		my $ping_interval = $self->{ping_interval};
		$inst->{cnn} = EV::Tarantool16->new({
			%{$self},
			%{$inst->{cfg}},
			# cnntrace => 1,
			connected    => sub {
				# undef $warned;
				$self->log_warn("Pool %s [%s]: connected", $self->{name}, $inst->{name})
					if do { ();$warned } ne do { $warned = "connect" };
				my $cnn = shift;
				$inst->{set_state}($inst, 'active');
				my $failcount = 0;
				my $loop;$loop = sub { my $loop = $loop;
					if ($cnn->ok) {
						$inst->{checker}($inst, $cnn, sub {
							my $res = shift;
							if ($res) {
								if ($res->{rw}) {
									$inst->{set_state}($inst, 'active-rw');
								}
								else {
									$inst->{set_state}($inst, 'active-ro');
								}
							}
							else {
								$self->log_error("Pool %s [%s] failed: %s",$self->{name}, $inst->{name}, $_[0]);
								$inst->{set_state}($inst, 'error');
							}
							if ($inst->{cv_ref}) { $inst->{cv_ref}->end; undef $inst->{cv_ref}; }
							unless ($res) {
								if ($failcount++ > 10) {
									$inst->{set_state}($inst, 'unavail');
									$cnn->reconnect;
									return;
								}
							}
							my $w; $w = AE::timer $ping_interval, 0, sub {
								undef $w;
								$loop->();
							};
						});
					}
				};$loop->();weaken($loop);
			},
			connfail     => sub {
				shift;
				$inst->{set_state}($inst, 'unavail');
				$self->log_warn("Pool %s [%s]: failed to connect: %s", $self->{name}, $inst->{name}, $_[0])
					if do { ();$warned } ne do { $warned = "connfail" };
				if ($inst->{cv_ref}) {
					$inst->{cv_ref}->end; undef $inst->{cv_ref};
				}
			},
			disconnected => sub {
				shift;
				$inst->{set_state}($inst, 'unavail');
				$self->log_warn("Pool %s [%s]: disconnected: %s", $self->{name}, $inst->{name}, $_[0])
					unless do { (); $warned } eq do { $warned = "disconnected" };
				if ($inst->{cv_ref}) {
					return unless $self->{log};
					$inst->{cv_ref}->end; undef $inst->{cv_ref};
				}
			},
		});
	}
	
	return $self;
}

sub connect {
	my ($self, $cb) = @_;
	my $cv = AE::cv;
	$cv->begin;
	for my $inst (@{$self->{peers}}) {
		$cv->begin;
		my $cv_ref = $cv;
		$inst->{cv_ref} = $cv_ref;
		$inst->{cnn}->connect;
	}
	$cv->cb(sub{
		$self->log_info("Pool %s initialized, status: %s", $self->{name}, $self->status);
		$cb->() if $cb;
	});
	$cv->end;
	return $self;
}


sub disconnect {
	my $self = shift;
	for my $inst (@{$self->{peers}}) {
		if (my $old = delete $inst->{cnn}) {
			$old->disconnect;
		}
	}
}

BEGIN {
	for my $method (qw(ping eval call lua select insert delete update)) {
		my $sub = sub {
			my $self = shift;
			my $cb = pop;
			my $inst = shift @{ $self->{rws} }
				or return $cb->(undef, "Not connected");
			push @{ $self->{rws} }, $inst;
			$inst->{cnn}->$method(@_,sub {
				local $_[ $_[0] ? 0 : 2 ]{peer} = $inst->{peer};
				$cb->(@_);
			});
		};
		{
			no strict 'refs';
			*$method = $sub;
		}
	}
}

1;
