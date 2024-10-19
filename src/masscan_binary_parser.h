#ifndef MASSCAN_BINARY_PARSER_H
#define MASSCAN_BINARY_PARSER_H
#include "masscan.h"

struct masscan_binary_parser;

/* Returns null on allocation failure. */
struct masscan_binary_parser *mbp_init(struct masscan_parser_source source);

/* Infallible */
void mbp_destroy(struct masscan_binary_parser *parser);

/* Returns 1 on success, 0 on eof, <0 on failure (check errno). This function may block. */
int mbp_next_record(struct masscan_binary_parser *parser, struct masscan_record *restrict record_p);
#endif
