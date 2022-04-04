package Promised::Command::Docker;
use strict;
use warnings;
our $VERSION = '2.0';
use Promise;
use Promised::Flow;
use Promised::Command;
use Promised::Command::Signals;

my $PlatformIsMacOSX = $^O eq 'darwin';

sub new ($%) {
  my $self = bless {}, shift;
  my $opts = {@_};
  $self->docker ($opts->{docker});
  $self->docker_run_options ($opts->{docker_run_options} || []);
  $self->image ($opts->{image}); # or undef
  $self->command ($opts->{command} || []);
  $self->logs ($opts->{logs}); # or undef
  $self->propagate_signal ($opts->{propagate_signal});
  $self->signal_before_destruction ($opts->{signal_before_destruction});
  $self->{no_tty} = $opts->{no_tty};
  return $self;
} # new

sub docker ($;$) {
  if (@_ > 1) {
    if (not defined $_[1]) {
      $_[0]->{docker} = ['docker'];
    } elsif (ref $_[1] eq 'ARRAY') {
      $_[0]->{docker} = [@{$_[1]}];
    } else {
      $_[0]->{docker} = [$_[1]];
    }
  }
  return $_[0]->{docker};
} # docker

sub docker_run_options ($;$) {
  if (@_ > 1) {
    $_[0]->{docker_run_options} = $_[1];
  }
  return $_[0]->{docker_run_options};
} # docker_run_options

sub image ($;$) {
  if (@_ > 1) {
    $_[0]->{image} = $_[1];
  }
  return $_[0]->{image};
} # image

sub command ($;$) {
  if (@_ > 1) {
    $_[0]->{command} = $_[1];
  }
  return $_[0]->{command};
} # command

sub logs ($;$) {
  if (@_ > 1) {
    $_[0]->{logs} = $_[1];
  }
  return $_[0]->{logs};
} # logs

sub propagate_signal ($;$) {
  if (@_ > 1) {
    $_[0]->{propagate_signal} = $_[1];
  }
  return $_[0]->{propagate_signal};
} # propagate_signal

sub signal_before_destruction ($;$) {
  if (@_ > 1) {
    $_[0]->{signal_before_destruction} = $_[1];
  }
  return $_[0]->{signal_before_destruction};
} # signal_before_destruction

my $DHH = $ENV{PROMISED_COMMAND_DOCKERHOST_HOST} // '';
my $NeedDH = 0;
unless (length $DHH) {
  if ($PlatformIsMacOSX) {
    $DHH = 'docker.for.mac.localhost';
  } else {
    $DHH = 'dockerhost';
    $NeedDH = 1;
  }
}
sub dockerhost_host_for_container ($) {
  return $DHH;
} # dockerhost_host_for_container

sub get_dockerhost_ipaddr ($) {
  my $self = $_[0];
  return Promise->resolve ($self->{dockerhost_ipaddr})
      if ref $self and defined $self->{dockerhost_ipaddr};
  return Promise->reject ("Can't get dockerhost IP address on Mac OS X")
      if $PlatformIsMacOSX;
  my $ip_cmd = Promised::Command->new ([qw{ip route list dev docker0}]);
  $ip_cmd->stdout (\my $ip);
  return $ip_cmd->run->then (sub { return $ip_cmd->wait })->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
    my @ip = split /\s+/, $ip;
    shift @ip;
    no warnings; # Odd number of elements
    my %ip = @ip;
    $ip = $ip{src};
    die "Can't get docker0's IP address" unless defined $ip and $ip =~ /\A[0-9.]+\z/;
    $self->{dockerhost_ipaddr} = $ip if ref $self;
    return $ip;
  });
} # get_dockerhost_ipaddr

sub get_container_ipaddr ($) {
  return $_[0]->{get_container_ipaddr};
} # get_container_ipaddr

sub _r (@) {
  return bless {@_}, 'Promised::Command::Result';
} # _r

sub _run ($$) {
  my ($p, $code) = @_;
  if (defined $p) {
    return $p->then ($code);
  } else {
    my $return = $code->();
    return undef unless defined $return;
    return $return;
  }
} # _run

sub start ($) {
  my $self = $_[0];

  my $image = $self->{image};
  return Promise->reject (_r is_error => 1, message => "|image| is not specified", name => 'docker')
      unless defined $image;
  
  return Promise->reject (_r is_error => 1, message => "|start| already invoked", name => 'docker')
      if defined $self->{self_pid};
  $self->{self_pid} = $$;
  my ($s_container_ipaddr, $err_container_ipaddr);
  $self->{get_container_ipaddr} = Promise->new (sub {
    ($s_container_ipaddr, $err_container_ipaddr) = @_;
  });

  return Promise->all ([
    $NeedDH ? $self->get_dockerhost_ipaddr : undef,
  ])->then (sub {
    $self->{run_cmd} = my $cmd = Promised::Command->new ([
      @{$self->docker},
      'run', '-d',
      ($self->{no_tty} ? () : ('-t')),
      ($NeedDH ? ('--add-host=dockerhost:' . $self->{dockerhost_ipaddr}) : ()),
      @{$self->docker_run_options},
      $image,
      @{$self->{command}},
    ]);
    $cmd->stdout (\($self->{container_id} = ''));
    $cmd->propagate_signal ($self->{propagate_signal});
    $cmd->signal_before_destruction ($self->{signal_before_destruction});
    $self->{running} = 1;

    if ($self->{propagate_signal}) {
      for my $name (qw(INT TERM QUIT)) {
        $self->{signal_handlers}->{$name}
            = Promised::Command::Signals->add_handler ($name => sub {
                return $self->stop (signal => $name);
              }, name => "Docker |$image|");
      }
    }
    
    return $cmd->run->then (sub {
      return $cmd->wait;
    })->then (sub {
      die $_[0] unless $_[0]->exit_code == 0;
      chomp $self->{container_id};
      delete $self->{run_cmd};

      my $cmd = Promised::Command->new ([
        @{$self->{docker}},
        'inspect',
        '--format', '{{ .NetworkSettings.IPAddress }}',
        $self->{container_id},
      ]);
      $cmd->stdout (\my $addr);
      $cmd->run->then (sub {
        return $cmd->wait;
      })->then (sub {
        chomp $addr;
        die "Failed to get docker container's IP address" unless $addr;
        $s_container_ipaddr->($addr);
      }, sub {
        $err_container_ipaddr->($_[0]);
      });

      my $p = _run undef, sub {
        my $logs = $self->{logs};
        return undef unless defined $logs;
        
        $self->{log_command} = Promised::Command->new ([
          @{$self->{docker}},
          'logs',
          '--follow',
          $self->{container_id},
        ]);
        $self->{log_command}->propagate_signal ($self->{propagate_signal});
        $self->{log_command}->signal_before_destruction (1);
        $self->{log_command}->stdout ($logs);
        return $self->{log_command}->run;
      };

      return _run $p, sub {
        return _r exit_code => 0, name => 'docker';
      };
    });
  });
} # start

sub stop ($;%) {
  my ($self, %args) = @_;
  my $signal = $args{signal} || 'TERM';

  my $p = _run undef, sub {
    return undef unless defined $self->{run_cmd};

    $self->{run_cmd}->send_signal ($signal eq 'KILL' ? $signal : 'INT');
    return $self->{run_cmd}->wait->catch (sub { });
  };

  $p = _run $p, sub {
    return Promise->resolve unless defined $self->{container_id};

    my $kc = $signal eq 'KILL' ? 'kill' : 'stop';
    my $cmd = Promised::Command->new
        (['docker', $kc, $self->{container_id}]);
    $cmd->stdout (\my $stdout);
    return $self->{stop_command}->{$kc} ||= $cmd->run->then (sub {
      return $cmd->wait;
    })->then (sub {
      die $_[0] unless $_[0]->exit_code == 0;
      delete $self->{signal_handlers};
      delete $self->{running};
      return $_[0];
    })->finally (sub {
      delete $self->{stop_command}->{$kc};
      return undef;
    });
  };

  return promised_cleanup {
    my $log_cmd = delete $self->{log_command};
    return unless defined $log_cmd;

    $log_cmd->send_signal ('TERM');
    return $log_cmd->wait->catch (sub { });
  } $p;
} # stop

sub DESTROY ($) {
  my $self = $_[0];
  if ($self->{running} and
      defined $self->{self_pid} and $self->{self_pid} == $$) {
    require Carp;
    warn "$$: $self is to be destroyed while the docker container is still running", Carp::shortmess;
    if (defined $self->{signal_before_destruction}) {
      $self->stop;
    }
  }
} # DESTROY

1;

=head1 LICENSE

Copyright 2015-2022 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
