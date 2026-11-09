use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

run_tests();

__DATA__

=== TEST 1: peers are ordered by address, add 6003 then 6002
--- http_config
    upstream backends {
        zone zone_for_backends 128k;
        server 127.0.0.1:6001;
    }
--- config
    location /dynamic {
        dynamic_upstream;
    }
    location /test {
        echo_location /dynamic upstream=backends&server=127.0.0.1:6003&add=;
        echo_location /dynamic upstream=backends&server=127.0.0.1:6002&add=;
    }
--- request
    GET /test
--- response_body
server 127.0.0.1:6001 addr=127.0.0.1:6001;
server 127.0.0.1:6003 addr=127.0.0.1:6003;
server 127.0.0.1:6001 addr=127.0.0.1:6001;
server 127.0.0.1:6002 addr=127.0.0.1:6002;
server 127.0.0.1:6003 addr=127.0.0.1:6003;


=== TEST 2: reverse insertion order yields the same final order
--- http_config
    upstream backends {
        zone zone_for_backends 128k;
        server 127.0.0.1:6001;
    }
--- config
    location /dynamic {
        dynamic_upstream;
    }
    location /test {
        echo_location /dynamic upstream=backends&server=127.0.0.1:6002&add=;
        echo_location /dynamic upstream=backends&server=127.0.0.1:6003&add=;
    }
--- request
    GET /test
--- response_body
server 127.0.0.1:6001 addr=127.0.0.1:6001;
server 127.0.0.1:6002 addr=127.0.0.1:6002;
server 127.0.0.1:6001 addr=127.0.0.1:6001;
server 127.0.0.1:6002 addr=127.0.0.1:6002;
server 127.0.0.1:6003 addr=127.0.0.1:6003;
