#!/usr/bin/perl

use LWP::UserAgent;
use JSON;
use Data::Dumper;
use Getopt::Long;

Getopt::Long::Configure("gnu_getopt");

my %backend_properties = (
  "_default"          =>
  {
    "max_connections"       => "800",
        "connect_timeout"       => "5s",
        "first_byte_timeout"    => "120s",
    "director_type"     => "round-robin"
  },
   #, "/exampleapp"       =>
   #{
   #  "max_connections"       => "1024",
   #  "director_type"         => "client"
   #}
);

my $opt_marathonurl = "http://mymarathonserver:8080", 
   $opt_format    = "varnish",
   $opt_app     = "*",
   $opt_help;

my $result  = GetOptions(
  "u|url=s"     => \$opt_marathonurl,
  "f|format=s"  => \$opt_format,
  "a|app=s"   => \$opt_app,
  "h|help"    => \$opt_help
);

sub showHelp {
  printf("\nUsage:\n" .
       "  %s [options].\n\n".
       "Valid options:\n".
       "  --url/-u <url>        = Marathon URL.\n" .
       "  --format/-f <format>  = Output format (nginx or varnish).\n" .
       "  --app/-a <appid>      = Only fetch config for a spesific appId.\n\n",
      $0); 

  exit(0);
}

showHelp if (!$result || $opt_help);

sub getTaskObject {
  my $cli = LWP::UserAgent->new;
  my $apiEndpoint = sprintf("%s/%s", $opt_marathonurl,
    ($opt_app eq "*") ? "v2/tasks" : 
    ("v2/apps/" . $opt_app . "/tasks"));

  my $resp = $cli->get($apiEndpoint);
	
  return $resp->is_success && @{decode_json($resp->content)->{"tasks"}};
}

sub getAppList {
  my @taskObject, $appList = {};

  @taskObject = getTaskObject() or
    return -1;

  foreach (@taskObject) {
    next if (!exists($_->{'healthCheckResults'}[0]{'alive'}) || 
  	         $_->{'healthCheckResults'}[0]{'alive'} < 1 ||
      	     !exists($_->{'host'}) || 
         	 !exists($_->{'ports'}[0]));

    $appId = $_->{'appId'};
  
    $obj = {
      'appId'  => $_->{'appId'},
      'taskId' => $_->{'id'},
      'host'   => $_->{'host'},
      'port'   => $_->{'ports'}[0]
     };

    push(@{$appList->{$appId}}, $obj);
  }

  return \%{$appList};
}

sub makeNginxConfig {
  my $appList = shift;

  foreach my $backend (sort keys %{$appList}) {
    printf("# appId: %s\n", @{$appList->{$backend}}[0]->{appId});
    printf("upstream %s {\n", $backend);
    foreach (sort {$a->{port} <=> $b->{port}} @{$appList->{$backend}}) {
      printf("  server %s:%s;\n", $_->{host}, $_->{port});
    }
    print("}\n\n");
  }
}

sub makeVarnishConfig {
  my $appList = shift;
  my $directorType = $backend_properties{"_default"}->{"backend_type"};

  foreach my $appId (sort keys %{$appList}) {
    printf("# appId: %s\n", @{$appList->{$appId}}[0]->{appId});
    my @backendList;
    my $props = "";

    my $propkey = exists($backend_properties{$appId}) ? 
      $appId : "_default";

    if (exists($backend_properties{$propkey})) {
      foreach(sort keys %{$backend_properties{$propkey}}) {
        if ($_ eq "director_type") {
          $directorType = $backend_properties{$propkey}->{$_};
          next
        }

        $props .= sprintf("  .%s = %s;\n", $_, $backend_properties{$propkey}->{$_});
      }
    }

    # Create backend definitions.
    $backendCount = scalar @{$appList->{$appId}};
    foreach (sort {$a->{port} <=> $b->{port}} @{$appList->{$appId}}) {

      $appId =~ s/^\///;
      $appId =~ s/\/|\.|\-/_/g;
  
      my $backendId = sprintf("%s%s", $appId, 
                ($backendCount > 1) ? ("_" . $_->{port}) : "");   


      printf("backend %s {\n" .
           "  .host = \"%s\";\n" .  
           "  .port = \"%s\";\n".
           "%s" .
           "}\n\n"
          , $backendId, 
          $_->{host}, 
          $_->{port},
          $props);

      if ($backendCount > 1) {
        push(@backendList, $backendId);
      } 
    }

    # Create director if we have more than one backend for the appId.
    if ($backendCount > 1) {
      printf("director %s %s {\n", $appId, $directorType);
      foreach (sort @backendList) {
        printf("  { .backend = %s; .weight  = 1; }\n", $_);
      }
      printf("}\n\n");
    }
  }
}

$apps = getAppList();

if ($opt_format eq "varnish") {
  makeVarnishConfig($apps);
} elsif ($opt_format eq "nginx") {
  makeNginxConfig($apps);
}

