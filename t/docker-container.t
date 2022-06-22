use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Promised::Command::Docker;
use Promised::Flow;

my $Docker = undef;

test {
  my $c = shift;
  my $cmd = Promised::Command::Docker->new (
    docker => $Docker,
    image => 'debian:sid',
    command => ['sleep', 100],
  );
  $cmd->start->then (sub {
    return $cmd->get_container_ipaddr;
  })->then (sub {
    my $r = $_[0];
    test {
      like $r, qr{\A[0-9]+(?:\.[0-9]+){3}\z};
    } $c;
    return $cmd->get_container_ipaddr->then (sub {
      my $r2 = $_[0];
      test {
        is $r2, $r;
      } $c;
      return $cmd->stop;
    });
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 2, name => 'get_container_ipaddr (object method)';

test {
  my $c = shift;
  my $cmd = Promised::Command::Docker->new (
    docker => $Docker,
    image => 'debian:sid',
    docker_run_options => [
      '--net', 'host',
    ],
    command => ['sleep', 100],
  );
  $cmd->start->then (sub {
    return $cmd->get_container_ipaddr;
  })->then (sub {
    my $r = $_[0];
    test {
      ok 0, $r;
    } $c;
  }, sub {
    my $e = $_[0];
    test {
      like $e, qr{Failed to get docker container's IP address}, $e;
    } $c;
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 1, name => 'get_container_ipaddr (object method), no IP address';

run_tests;

=head1 LICENSE

Copyright 2017-2022 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
