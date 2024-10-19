#ifndef MASSCAN_H
#define MASSCAN_H
#include <stdio.h>

/* yoink */

struct ip_address {
    union {
        // native endian
        unsigned ipv4;
        // ???
        char ipv6[16];
    } v;
    unsigned char version;
};

enum masscan_app_proto {
    PROTO_NONE,
    PROTO_HEUR,
    PROTO_SSH1,
    PROTO_SSH2,
    PROTO_HTTP,
    PROTO_FTP,
    PROTO_DNS_VERSIONBIND,
    PROTO_SNMP,             /* 7 - simple network management protocol, udp/161 */
    PROTO_NBTSTAT,          /* 8 - netbios, udp/137 */
    PROTO_SSL3,
    PROTO_SMB,              /* 10 - SMB tcp/139 and tcp/445 */
    PROTO_SMTP,             /* 11 - transfering email */
    PROTO_POP3,             /* 12 - fetching email */
    PROTO_IMAP4,            /* 13 - fetching email */
    PROTO_UDP_ZEROACCESS,
    PROTO_X509_CERT,        /* 15 - just the cert */
    PROTO_X509_CACERT,
    PROTO_HTML_TITLE,
    PROTO_HTML_FULL,
    PROTO_NTP,              /* 19 - network time protocol, udp/123 */
    PROTO_VULN,
    PROTO_HEARTBLEED,
    PROTO_TICKETBLEED,
    PROTO_VNC_OLD,
    PROTO_SAFE,
    PROTO_MEMCACHED,        /* 25 - memcached */
    PROTO_SCRIPTING,
    PROTO_VERSIONING,
    PROTO_COAP,             /* 28 - constrained app proto, udp/5683, RFC7252 */
    PROTO_TELNET,           /* 29 - ye old remote terminal */
    PROTO_RDP,              /* 30 - Microsoft Remote Desktop Protocol tcp/3389 */
    PROTO_HTTP_SERVER,      /* 31 - HTTP "Server:" field */
    PROTO_MC,               /* 32 - Minecraft server */
    PROTO_VNC_RFB,
    PROTO_VNC_INFO,
    PROTO_ISAKMP,           /* 35 - IPsec key exchange */

    PROTO_ERROR,

    PROTO_end_of_list /* must be last one */
};

struct masscan_record {
    unsigned char is_open;
    unsigned long timestamp;
    struct ip_address ip;
    unsigned char ip_proto;
    unsigned short port;
    unsigned char reason;
    unsigned char ttl;
    unsigned char mac[6];
    enum masscan_app_proto app_proto;
};

enum masscan_parser_source_type {
    MASSCAN_PARSER_SRC_FILEP,
    MASSCAN_PARSER_SRC_MEMORY,
};

struct masscan_parser_source {
    enum masscan_parser_source_type type;
    union {
        FILE *fp;
        struct {
            const char *ptr;
            size_t len;
        } mem;
    } v;
};

#endif
