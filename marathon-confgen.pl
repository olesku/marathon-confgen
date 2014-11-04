#!/usr/bin/perl

use LWP::UserAgent;
use JSON;
use Data::Dumper;
use Getopt::Long;

Getopt::Long::Configure("gnu_getopt");

my $opt_marathonurl = "", 
   $opt_format 		= "varnish",
   $opt_app			= "*",
   $opt_help;

my $result  = GetOptions(
	"u|url=s" 		=> \$opt_marathonurl,
	"f|format=s" 	=> \$opt_format,
	"a|app=s"		=> \$opt_app,
	"h|help"		=> \$opt_help
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
		$appId =~ s/^\///;
		$appId =~ s/\/|\.|\-/_/g;
		

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

	foreach my $appId (sort keys %{$appList}) {
		printf("# appId: %s\n", @{$appList->{$appId}}[0]->{appId});
		my @backendList;

		# Create backend definitions.
		$backendCount = scalar @{$appList->{$appId}};
		foreach (sort {$a->{port} <=> $b->{port}} @{$appList->{$appId}}) {
			my $backendId = sprintf("%s%s", $appId, 
								($backendCount > 1) ? ("_" . $_->{port}) : "");		

			printf("backend %s {\n" .
				   "  .host = \"%s\";\n" .  
				   "  .port = \"%s\";\n".
				   "}\n\n"
				  , $backendId, 
					$_->{host}, 
					$_->{port});

		 	if ($backendCount > 1) {
				push(@backendList, $backendId);
			} 
		}

		# Create director if we have more than one backend for the appId.
		if ($backendCount > 1) {
			printf("director %s client {\n", $appId);
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

