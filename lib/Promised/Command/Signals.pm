package Promised::Command::Signals;
use strict;
use warnings;
our $VERSION = '1.0';
use AnyEvent;
use Promise;

my $Sig = {};
my $Handlers = {};

our $Action = {
  HUP => 'die',
  INT => 'die',
  QUIT => 'die',
  TERM => 'die',
};

my $DEBUG = $ENV{PROMISED_COMMAND_DEBUG};

sub load_modules () {
  require Carp;
  require AbortController;
}

sub add_handler ($$$;%) {
  my (undef, $signal, $code, %args) = @_;
  return if $Handlers->{$signal}->{$code};
  my $name = '';
  if ($DEBUG) {
    if (defined $args{name}) {
      $name = '' . $args{name};
    } else {
      require Carp;
      $name = $code . Carp::shortmess ();
    }
  }
  unless (keys %{$Handlers->{$signal} or {}}) {
    $Sig->{$signal} = AE::signal $signal => sub {
      my $canceled;
      my $cancel = sub { $canceled = 1 };
      AE::log alert => "SIG$signal received";
      Promise->all ([
        map {
          my ($code, $name) = @$_;
          AE::log alert => qq{Running signal handler "$name"...} if $DEBUG;
          Promise->resolve ($cancel)->then ($code)->finally (sub {
            AE::log alert => qq{Signal handler "$name" done} if $DEBUG;
          })->catch (sub {
            AE::log alert => qq{Died within signal handler "$name": $_[0]};
          });
        } values %{$Handlers->{$signal} or {}},
      ])->then (sub {
        return if $canceled;
        my $action = $Action->{$signal} || 'die';
        unless ($action eq 'ignore') {
          AE::log alert => "terminated by SIG$signal";
          exit 1;
        }
      });
    };
    AE::log alert => "Promised::Command::Signals handler for SIG$signal installed" if $DEBUG;
  }
  $Handlers->{$signal}->{$code} = [$code, $name];
  AE::log alert => qq{A SIG$signal handler "$name" added} if $DEBUG;
  return bless [$signal, $code], 'Promised::Command::Signals::Handler';
} # add_handler

sub _remove_handler ($$$) {
  my (undef, $signal, $code) = @_;
  delete $Handlers->{$signal}->{$code};
  delete $Sig->{$signal} unless keys %{$Handlers->{$signal}};
} # _remove_handler

my $GlobalAbortControllers = [];

sub abort_signal ($) {
  my $class = shift;
  require AbortController;
  my $ac = AbortController->new;
  my $v = {ac => $ac, sigs => {}};
  push @$GlobalAbortControllers, $v;
  $v->{sigs}->{$_} = $class->add_handler ($_ => sub {
    $_[0]->(); # cancel signal
    $ac->abort;
    $GlobalAbortControllers = [grep {
      $_->{ac} ne $ac;
    } @$GlobalAbortControllers];
  }) for qw(INT QUIT TERM);
  return $ac->signal;
} # abort_signal

package Promised::Command::Signals::Handler;

sub DESTROY ($) {
  Promised::Command::Signals->_remove_handler (@{$_[0]});
} # DESTROY

1;

=head1 LICENSE

Copyright 2015-2022 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
