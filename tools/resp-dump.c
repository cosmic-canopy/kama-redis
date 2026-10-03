/* resp-dump — hiredis's reading of RESP bytes, for tools/gen-resp-vectors.sh. It is generator-only C: it is
 * compiled against the pinned hiredis sources in a temporary directory, run, and thrown away. Nothing here is
 * part of the package, which has no C.
 *
 *   resp-dump capture   Runs hiredis's own reader tests (test.c's test_reply_reader) with redisReaderCreate and
 *                       redisReaderFeed wrapped, and prints one line per reader those tests fed:
 *                       <test name> TAB <the reader's maxelements> TAB <every byte fed to it, in hex>.
 *   resp-dump read      Reads lines <maxelements> TAB <hex> and prints, per line, what a fresh reader with that
 *                       maxelements makes of the bytes: each reply, then how it ended. One line, in the same
 *                       notation as tests/unit/src/resp_test.kama's `describe`:
 *                         simple:<hex> error:<hex> int:<n> double:<16 hex digits of the bits>|double:nan
 *                         bool:t|f null bignum:<hex> bulk:<hex> verbatim:<hex>:<hex>
 *                         array[..] map[..] set[..] push[..] hiredisattr[..]
 *                       replies joined by " ; ", then "|end" (nothing left over), "|more" (a reply begun and not
 *                       finished) or "|error:<errstr>".
 */
#include "fmacros.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "hiredis.h"
#include "read.h"

/* ---- describing a reply ---- */

static void hex(FILE *o, const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) fprintf(o, "%02x", (unsigned char)s[i]);
}

static void describe(FILE *o, const redisReply *r) {
    size_t i;
    const char *open = NULL;
    switch (r->type) {
    case REDIS_REPLY_STATUS: fputs("simple:", o); hex(o, r->str, r->len); return;
    case REDIS_REPLY_ERROR: fputs("error:", o); hex(o, r->str, r->len); return;
    case REDIS_REPLY_INTEGER: fprintf(o, "int:%lld", r->integer); return;
    case REDIS_REPLY_DOUBLE: {
        if (isnan(r->dval)) { fputs("double:nan", o); return; }
        unsigned long long bits;
        memcpy(&bits, &r->dval, sizeof bits);
        fprintf(o, "double:%016llx", bits);
        return;
    }
    case REDIS_REPLY_BOOL: fputs(r->integer ? "bool:t" : "bool:f", o); return;
    case REDIS_REPLY_NIL: fputs("null", o); return;
    case REDIS_REPLY_BIGNUM: fputs("bignum:", o); hex(o, r->str, r->len); return;
    case REDIS_REPLY_STRING: fputs("bulk:", o); hex(o, r->str, r->len); return;
    case REDIS_REPLY_VERB: fputs("verbatim:", o); hex(o, r->vtype, strlen(r->vtype)); fputs(":", o); hex(o, r->str, r->len); return;
    case REDIS_REPLY_ARRAY: open = "array["; break;
    case REDIS_REPLY_MAP: open = "map["; break;
    case REDIS_REPLY_SET: open = "set["; break;
    case REDIS_REPLY_PUSH: open = "push["; break;
    case REDIS_REPLY_ATTR: open = "hiredisattr["; break;
    default: fprintf(o, "unknown%d", r->type); return;
    }
    fputs(open, o);
    for (i = 0; i < r->elements; i++) {
        if (i > 0) fputs(",", o);
        describe(o, r->element[i]);
    }
    fputs("]", o);
}

static int unhex(const char *h, char *out, size_t *n) {
    size_t len = strlen(h), i;
    if (len % 2) return -1;
    for (i = 0; i < len / 2; i++) {
        unsigned v;
        if (sscanf(h + 2 * i, "%2x", &v) != 1) return -1;
        out[i] = (char)v;
    }
    *n = len / 2;
    return 0;
}

static int readMode(void) {
    size_t cap = 1 << 20;
    char *line = malloc(cap), *bytes = malloc(cap);
    while (fgets(line, (int)cap, stdin)) {
        size_t n = strlen(line);
        if (n + 1 >= cap) { fprintf(stderr, "resp-dump: line too long\n"); return 2; }
        if (n && line[n - 1] == '\n') line[--n] = 0;
        char *tab = strchr(line, '\t');
        if (!tab) { fprintf(stderr, "resp-dump: no tab\n"); return 2; }
        *tab = 0;
        long long maxelements = atoll(line);
        size_t len;
        if (unhex(tab + 1, bytes, &len)) { fprintf(stderr, "resp-dump: bad hex\n"); return 2; }
        redisReader *r = redisReaderCreate();
        r->maxelements = maxelements;
        if (len) redisReaderFeed(r, bytes, len);
        int any = 0;
        for (;;) {
            void *reply = NULL;
            if (redisReaderGetReply(r, &reply) != REDIS_OK) {
                printf("|error:%s\n", r->errstr);
                break;
            }
            if (reply == NULL) {
                /* Nothing left over: every byte read, and no reply begun. After a reply, GetReply arms the
                 * root task (ridx 0, type -1) before it finds there is nothing more to read. */
                int idle = r->pos == r->len && (r->ridx == -1 || (r->ridx == 0 && r->task[0]->type < 0));
                printf(idle ? "|end\n" : "|more\n");
                break;
            }
            if (any) fputs(" ; ", stdout);
            describe(stdout, reply);
            freeReplyObject(reply);
            any = 1;
        }
        redisReaderFree(r);
    }
    return 0;
}

/* ---- capturing the inputs of hiredis's reader tests ---- */

static char testName[512];
static char caseName[512];
static char *fed = NULL;
static size_t fedLen = 0, fedCap = 0;
static long long fedMax = 0;
static int fresh = 0, open_ = 0;
static redisReader *current = NULL;

static void flushCase(void) {
    if (!open_) return;
    printf("%s\t%lld\t", caseName, fedMax);
    hex(stdout, fed, fedLen);
    putchar('\n');
    open_ = 0;
    fedLen = 0;
}

static redisReader *captureCreate(void) {
    fresh = 1;
    return redisReaderCreate();
}

static int captureFeed(redisReader *r, const char *buf, size_t len) {
    if (fresh || r != current) {
        flushCase();
        open_ = 1;
        memcpy(caseName, testName, sizeof caseName);
        fedMax = r->maxelements;
        current = r;
        fresh = 0;
    }
    if (fedLen + len > fedCap) {
        fedCap = (fedLen + len) * 2;
        fed = realloc(fed, fedCap);
    }
    memcpy(fed + fedLen, buf, len);
    fedLen += len;
    return redisReaderFeed(r, buf, len);
}

/* test.c's test() macro prints "#NN " and then the name as a format, ending in ": ". The name is what we keep;
 * every other line it prints goes to stderr. */
static int capturePrintf(const char *fmt, ...) {
    size_t n = strlen(fmt);
    if (n >= 2 && strcmp(fmt + n - 2, ": ") == 0 && fmt[0] != '#') {
        snprintf(testName, sizeof testName, "%.*s", (int)(n - 2), fmt);
        return 0;
    }
    va_list ap;
    va_start(ap, fmt);
    int k = vfprintf(stderr, fmt, ap);
    va_end(ap);
    return k;
}

#define redisReaderCreate() captureCreate()
#define redisReaderFeed(r, b, l) captureFeed((r), (b), (l))
#define printf capturePrintf
#define main hiredis_test_main
#include "test.c"
#undef main
#undef printf
#undef redisReaderFeed
#undef redisReaderCreate

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "capture") == 0) {
        test_reply_reader();
        flushCase();
        return fails ? 1 : 0;
    }
    if (argc == 2 && strcmp(argv[1], "read") == 0) return readMode();
    fprintf(stderr, "usage: resp-dump capture | read\n");
    return 2;
}
