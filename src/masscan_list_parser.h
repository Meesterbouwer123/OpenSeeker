#ifndef MASSCAN_LIST_PARSER_H
#define MASSCAN_LIST_PARSER_H
#include "masscan.h"

#define MASSCAN_LIST_PARSER_MAX_LINE_LEN 256

struct masscan_list_parser;

/* Returns null on allocation failure. */
struct masscan_list_parser *mlp_init(struct masscan_parser_source source);

/* Infallible */
void mlp_destroy(struct masscan_list_parser *parser);

/* Returns 1 on success, 0 on eof, <0 on failure (check errno). This function may block. */
int mlp_next_record(struct masscan_list_parser *parser, struct masscan_record *record_p);
#endif
