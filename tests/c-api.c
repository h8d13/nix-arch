/* Smoke the C ABI end-to-end so libstore-c/libutil-c can't drift
 * silently: build.sh only proves they compile and link; this proves
 * open/query actually work through the C surface. Open a store on a
 * fresh root (creates the SQLite db), read back uri/storedir/version,
 * parse a dummy path and confirm it's not valid in an empty store.
 * TAP output, root comes in as argv[1] like the other tests. */
#include <stdio.h>
#include <string.h>

#include <nix_api_util.h>
#include <nix_api_store.h>

static int n = 0, fail = 0;

static void ok(int cond, const char * name)
{
	n++;
	printf("%sok %d - %s\n", cond ? "" : "not ", n, name);
	if (!cond)
		fail = 1;
}

static void grab(const char * start, unsigned int len, void * user_data)
{
	snprintf(user_data, 512, "%.*s", len, start);
}

int main(int argc, char ** argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s <store-root>\n", argv[0]);
		return 1;
	}

	nix_c_context * ctx = nix_c_context_create();
	ok(nix_libstore_init_no_load_config(ctx) == NIX_OK, "libstore init");

	Store * store = nix_store_open(ctx, argv[1], NULL);
	ok(store != NULL, "open store on fresh root");
	if (!store) {
		fprintf(stderr, "# %s\n", nix_err_msg(NULL, ctx, NULL));
		printf("1..%d\n", n);
		return 1;
	}

	char buf[512] = "";
	ok(nix_store_get_uri(ctx, store, grab, buf) == NIX_OK && buf[0],
		"get_uri");
	fprintf(stderr, "# uri: %s\n", buf);

	buf[0] = '\0';
	ok(nix_store_get_storedir(ctx, store, grab, buf) == NIX_OK
			&& strstr(buf, "/nix/store"),
		"get_storedir mentions /nix/store");

	buf[0] = '\0';
	ok(nix_store_get_version(ctx, store, grab, buf) == NIX_OK && buf[0],
		"get_version");
	fprintf(stderr, "# version: %s\n", buf);

	char path[600];
	snprintf(path, sizeof(path),
		"%s/ffffffffffffffffffffffffffffffff-x",
		"/nix/store");
	StorePath * sp = nix_store_parse_path(ctx, store, path);
	ok(sp != NULL, "parse dummy store path");
	if (sp) {
		ok(!nix_store_is_valid_path(ctx, store, sp),
			"dummy path invalid in empty store");
		nix_store_path_free(sp);
	}

	nix_store_free(store);
	nix_c_context_free(ctx);
	printf("1..%d\n", n);
	return fail;
}
